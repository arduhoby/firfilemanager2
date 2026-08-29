import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;

import '../models/connection_profile.dart';
import '../models/file_entry.dart';
import '../models/transfer_progress.dart';
import '../hidden_entry_policy.dart';
import '../storage_provider.dart';

/// A [StorageProvider] that connects to FTP/FTPS servers using `ftpconnect`.
class FtpProvider implements StorageProvider {
  FtpProvider({required this.profile, required this.password});

  @override
  final ConnectionProfile profile;

  final String? password;

  FTPConnect? _ftp;
  bool _isConnected = false;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  String get displayName =>
      '${profile.type == ConnectionType.ftps ? "FTPS" : "FTP"}: ${profile.name}';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  @override
  Future<void> connect() async {
    try {
      final user = profile.authMethod == AuthMethod.anonymous
          ? 'anonymous'
          : (profile.username ?? 'anonymous');
      final pass = profile.authMethod == AuthMethod.anonymous
          ? 'anonymous@'
          : (password ?? '');

      final isFtps = profile.type == ConnectionType.ftps;
      final primarySecurity = isFtps
          ? (profile.effectivePort == 990
                ? SecurityType.ftps
                : SecurityType.ftpes)
          : SecurityType.ftp;

      _ftp = FTPConnect(
        profile.host!,
        port: profile.effectivePort,
        user: user,
        pass: pass,
        securityType: primarySecurity,
        timeout: 30,
      );

      try {
        await _ftp!.connect();
      } catch (e) {
        if (isFtps) {
          final fallbackSecurity = primarySecurity == SecurityType.ftps
              ? SecurityType.ftpes
              : SecurityType.ftps;
          _ftp = FTPConnect(
            profile.host!,
            port: profile.effectivePort,
            user: user,
            pass: pass,
            securityType: fallbackSecurity,
            timeout: 30,
          );
          await _ftp!.connect();
        } else {
          rethrow;
        }
      }

      _isConnected = true;
      _connectionController.add(true);
    } catch (e) {
      _isConnected = false;
      throw StorageException(
        'FTP bağlantısı başarısız: $e',
        code: StorageException.networkError,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_ftp != null) {
      try {
        await _ftp!.disconnect();
      } catch (_) {}
      _ftp = null;
    }
    _isConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
      await _connectionController.close();
    }
  }

  /// Always join FTP paths with forward slashes regardless of OS
  static String _ftpJoin(String parent, String child) {
    final cleanParent = parent
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final cleanChild = child.replaceAll('\\', '/');
    if (cleanParent.isEmpty || cleanParent == '/') {
      return '/$cleanChild';
    }
    return '$cleanParent/$cleanChild';
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!_isConnected || _ftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    final ftpPath = path.replaceAll('\\', '/');

    try {
      await _ftp!.changeDirectory('/');
      if (ftpPath != '/') {
        await _ftp!.changeDirectory(ftpPath);
      }

      List<FileEntry> entries;
      try {
        entries = await _safeFtpList(ftpPath);
      } catch (e) {
        debugPrint(
          'FTP _safeFtpList failed: $e, trying listDirectoryContent fallback...',
        );
        final items = await _ftp!.listDirectoryContent();
        entries = items
            .where((item) => item.name != '.' && item.name != '..')
            .map(
              (item) => FileEntry(
                name: item.name,
                path: _ftpJoin(ftpPath, item.name),
                isDirectory: item.type == FTPEntryType.dir,
                size: item.size ?? 0,
                modified: item.modifyTime,
                hidden: HiddenEntryPolicy.isDotHidden(item.name),
              ),
            )
            .toList();
      }

      final showHidden = options?.showHidden ?? false;
      if (!showHidden) {
        entries = entries
            .where((e) => !HiddenEntryPolicy.isDotHidden(e.name))
            .toList();
      }
      return entries;
    } catch (e) {
      throw StorageException(
        'FTP list failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  /// Custom robust FTP listing via passive data socket
  Future<List<FileEntry>> _safeFtpList(String ftpPath) async {
    final pasvReply = await _ftp!.sendCustomCommand('PASV');
    final pasvMessage = pasvReply.message as String;
    if (!pasvReply.isSuccessCode()) {
      throw StorageException(
        'PASV failed: $pasvMessage',
        code: StorageException.networkError,
      );
    }

    final match = RegExp(r'\((?:(\d+),){5}(\d+)\)').firstMatch(pasvMessage);
    if (match == null) {
      throw StorageException(
        'Invalid PASV response: $pasvMessage',
        code: StorageException.networkError,
      );
    }

    final List<int> nums = pasvMessage
        .substring(match.start + 1, match.end - 1)
        .split(',')
        .map(int.parse)
        .toList();
    final pasvPort = (nums[4] * 256) + nums[5];

    final dataSocket = await Socket.connect(
      profile.host!,
      pasvPort,
      timeout: const Duration(seconds: 10),
    );

    final listReply = await _ftp!.sendCustomCommand('LIST');
    if (!listReply.isSuccessCode() &&
        listReply.code != 150 &&
        listReply.code != 125) {
      await dataSocket.close();
      throw StorageException(
        'LIST failed: ${listReply.message}',
        code: StorageException.networkError,
      );
    }

    final bytes = <int>[];
    await dataSocket.listen((chunk) {
      bytes.addAll(chunk);
    }).asFuture();

    await dataSocket.close();

    final rawText = const Utf8Codec(allowMalformed: true).decode(bytes);
    final lines = rawText.split(RegExp(r'\r?\n'));

    final results = <FileEntry>[];
    for (final line in lines) {
      final parsed = _parseFtpLine(line, ftpPath);
      if (parsed != null) {
        results.add(parsed);
      }
    }
    return results;
  }

  /// Parses Unix, IIS, MLSD, and simple FTP response lines safely
  FileEntry? _parseFtpLine(String rawLine, String dirPath) {
    final line = rawLine.trim();
    if (line.isEmpty ||
        line == '.' ||
        line == '..' ||
        line.startsWith('total '))
      return null;

    // 1. MLSD format: "type=dir;modify=20260803...; filename"
    if (line.contains(';')) {
      final parts = line.split(';');
      String name = '';
      bool isDir = false;
      int size = 0;
      DateTime? modified;

      for (var part in parts) {
        part = part.trim();
        if (part.isEmpty) continue;
        final eqIdx = part.indexOf('=');
        if (eqIdx == -1) {
          name = part;
        } else {
          final key = part.substring(0, eqIdx).toLowerCase();
          final val = part.substring(eqIdx + 1);
          if (key == 'type') {
            isDir = val.toLowerCase() == 'dir';
          } else if (key == 'size') {
            size = int.tryParse(val) ?? 0;
          } else if (key == 'modify' && val.length >= 8) {
            try {
              final y = int.parse(val.substring(0, 4));
              final m = int.parse(val.substring(4, 6));
              final d = int.parse(val.substring(6, 8));
              var hh = 0, mm = 0, ss = 0;
              if (val.length >= 14) {
                hh = int.parse(val.substring(8, 10));
                mm = int.parse(val.substring(10, 12));
                ss = int.parse(val.substring(12, 14));
              }
              modified = DateTime.utc(y, m, d, hh, mm, ss);
            } catch (_) {}
          }
        }
      }
      if (name.isNotEmpty && name != '.' && name != '..') {
        return FileEntry(
          name: name,
          path: _ftpJoin(dirPath, name),
          isDirectory: isDir,
          size: size,
          modified: modified,
          hidden: HiddenEntryPolicy.isDotHidden(name),
        );
      }
    }

    // 2. IIS Windows format: "02-11-15  03:05PM  <DIR>  folderName"
    final iisMatch = RegExp(
      r'^\d{2}-\d{2}-\d{2,4}\s+\d{2}:\d{2}(?:AM|PM)?\s+(<DIR>|\d+)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (iisMatch != null) {
      final typeOrSize = iisMatch.group(1)!;
      final name = iisMatch.group(2)!.trim();
      final isDir = typeOrSize.toUpperCase() == '<DIR>';
      final size = isDir ? 0 : (int.tryParse(typeOrSize) ?? 0);
      if (name != '.' && name != '..') {
        return FileEntry(
          name: name,
          path: _ftpJoin(dirPath, name),
          isDirectory: isDir,
          size: size,
          hidden: HiddenEntryPolicy.isDotHidden(name),
        );
      }
    }

    // 3. Unix ls -l format: "drwxr-xr-x  2 root  root  4096 Aug  3 23:44 folder"
    if (line.startsWith('d') || line.startsWith('-') || line.startsWith('l')) {
      final isDir = line.startsWith('d');
      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.length >= 8) {
        final name = tokens.sublist(8).join(' ');
        final size = int.tryParse(tokens[4]) ?? 0;
        if (name.isNotEmpty && name != '.' && name != '..') {
          return FileEntry(
            name: name,
            path: _ftpJoin(dirPath, name),
            isDirectory: isDir,
            size: size,
            hidden: HiddenEntryPolicy.isDotHidden(name),
          );
        }
      }
    }

    // 4. Raw filename fallback
    if (line.isNotEmpty &&
        line != '.' &&
        line != '..' &&
        !line.startsWith('226 ') &&
        !line.startsWith('150 ')) {
      final cleanName = line.endsWith('/')
          ? line.substring(0, line.length - 1)
          : line;
      return FileEntry(
        name: cleanName,
        path: _ftpJoin(dirPath, cleanName),
        isDirectory: line.endsWith('/'),
        size: 0,
        hidden: HiddenEntryPolicy.isDotHidden(cleanName),
      );
    }

    return null;
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!_isConnected || _ftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    // FTP doesn't have a direct stat command, use listdir on parent
    // Use instance dirname/basename (FTP-safe, forward slashes) not p.dirname/p.basename
    final parent = dirname(path);
    final name = basename(path);
    final entries = await list(parent);
    final entry = entries.where((e) => e.name == name).firstOrNull;
    if (entry == null) {
      throw StorageException(
        'Not found',
        code: StorageException.notFound,
        path: path,
      );
    }
    return entry;
  }

  @override
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  }) async* {
    if (!_isConnected || _ftp == null) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      // FTPConnect downloads to a local file, then we read it
      // This is a limitation of ftpconnect — it doesn't support streaming directly
      final tempDir = await Directory.systemTemp.createTemp('ftp_download_');
      final tempFile = File('${tempDir.path}/${p.basename(path)}');

      await _ftp!.downloadFile(path, tempFile);

      final bytes = tempFile.readAsBytesSync();
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        bytesTransferred: bytes.length,
        totalBytes: bytes.length,
      );

      // Clean up temp file
      tempFile.deleteSync();
      tempDir.deleteSync();
    } catch (e) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: e.toString(),
      );
    }
  }

  @override
  Stream<TransferProgress> write(
    String path,
    Stream<List<int>> data, {
    CancelToken? cancelToken,
  }) async* {
    if (!_isConnected || _ftp == null) {
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      // Phase 1: Write incoming data to a local temp file
      final tempDir = await Directory.systemTemp.createTemp('ftp_upload_');
      final tempFile = File('${tempDir.path}/${basename(path)}');

      final sink = tempFile.openWrite();
      var bytesWritten = 0;

      await for (final chunk in data) {
        if (cancelToken?.isCancelled ?? false) {
          await sink.close();
          tempFile.deleteSync();
          tempDir.deleteSync();
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.cancelled,
          );
          return;
        }
        sink.add(chunk);
        bytesWritten += chunk.length;
      }

      await sink.flush();
      await sink.close();

      // Phase 2: Upload temp file to FTP server
      // Signal that we are now uploading (indeterminate — ftpconnect has no upload progress callback)
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.inProgress,
        bytesTransferred: 0,
        totalBytes: bytesWritten,
      );

      // Navigate to the correct directory before uploading
      final ftpDir = dirname(path);
      await _ftp!.changeDirectory('/');
      if (ftpDir != '/') await _ftp!.changeDirectory(ftpDir);

      await _ftp!.uploadFile(tempFile);

      tempFile.deleteSync();
      tempDir.deleteSync();

      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.completed,
        bytesTransferred: bytesWritten,
        totalBytes: bytesWritten,
      );
    } catch (e) {
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: e.toString(),
      );
    }
  }

  @override
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options = const CopyOptions(),
    CancelToken? cancelToken,
  }) async* {
    // Cross-provider: pipe read to write
    final controller = StreamController<List<int>>();
    var bytesTransferred = 0;

    // Start reading in background
    read(sourcePath, cancelToken: cancelToken).listen((progress) {
      if (progress.state == TransferState.failed) {
        controller.addError(progress.error ?? 'Read failed');
      }
    });

    // For FTP, we need to download to temp then stream
    try {
      final tempDir = await Directory.systemTemp.createTemp('ftp_copy_');
      final tempFile = File('${tempDir.path}/${p.basename(sourcePath)}');

      await _ftp!.downloadFile(sourcePath, tempFile);
      final bytes = tempFile.readAsBytesSync();
      bytesTransferred = bytes.length;

      controller.add(bytes);
      controller.close();

      // Write to dest
      await for (final progress in destProvider.write(
        destPath,
        controller.stream,
        cancelToken: cancelToken,
      )) {
        yield progress.copyWith(
          operation: TransferOperation.copy,
          bytesTransferred: bytesTransferred,
        );
      }

      tempFile.deleteSync();
      tempDir.deleteSync();
    } catch (e) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.failed,
        error: e.toString(),
      );
    }
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    if (!_isConnected || _ftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      await _ftp!.rename(sourcePath, destPath);
    } catch (e) {
      throw StorageException(
        'FTP move failed: $e',
        code: StorageException.networkError,
        path: sourcePath,
        cause: e,
      );
    }
  }

  @override
  Future<void> rename(String path, String newName) async {
    // Use FTP-safe path helpers (forward slashes) not p.dirname/p.join
    final parent = dirname(path);
    final newPath = joinPath(parent, newName);
    await move(path, newPath);
  }

  @override
  Future<void> delete(String path) async {
    if (!_isConnected || _ftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      // Check if it's a directory or file
      final entry = await stat(path);
      if (entry.isDirectory) {
        // Recursively delete
        final entries = await list(path);
        for (final e in entries) {
          await delete(e.path);
        }
        await _ftp!.deleteDirectory(path);
      } else {
        await _ftp!.deleteFile(path);
      }
    } catch (e) {
      throw StorageException(
        'FTP delete failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<void> mkdir(String path) async {
    if (!_isConnected || _ftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      await _ftp!.makeDirectory(path);
    } catch (e) {
      throw StorageException(
        'FTP mkdir failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> get homePath async => profile.defaultPath;

  @override
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path) async => null;

  @override
  String normalizePath(String path) {
    // FTP paths always use forward slashes
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'/{2,}'), '/');
  }

  @override
  String joinPath(String parent, String child) => _ftpJoin(parent, child);

  @override
  String basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').where((s) => s.isNotEmpty).lastOrNull ??
        normalized;
  }

  @override
  String dirname(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length <= 1) return '/';
    return '/${segments.take(segments.length - 1).join('/')}';
  }

  @override
  Future<List<FileEntry>> search(
    String path,
    String query, {
    bool recursive = false,
  }) async {
    final results = <FileEntry>[];
    final queryLower = query.toLowerCase();

    Future<void> doSearch(String currentPath) async {
      final entries = await list(currentPath);
      for (final entry in entries) {
        if (entry.name.toLowerCase().contains(queryLower)) {
          results.add(entry);
        }
        if (recursive && entry.isDirectory) {
          try {
            await doSearch(entry.path);
          } catch (_) {
            // Ignore directory list errors
          }
        }
      }
    }

    await doSearch(path);
    return results;
  }

  @override
  bool supports(ProviderCapability capability) {
    switch (capability) {
      case ProviderCapability.read:
      case ProviderCapability.write:
      case ProviderCapability.delete:
      case ProviderCapability.move:
      case ProviderCapability.mkdir:
      case ProviderCapability.list:
      case ProviderCapability.search:
        return true;
      case ProviderCapability.streaming:
      case ProviderCapability.freeSpace:
      case ProviderCapability.symlinks:
      case ProviderCapability.permissions:
        return false;
    }
  }
}
