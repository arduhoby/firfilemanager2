import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../models/connection_profile.dart';
import '../models/file_entry.dart';
import '../models/transfer_progress.dart';
import '../hidden_entry_policy.dart';
import '../storage_provider.dart';

/// A [StorageProvider] that connects to SFTP servers using `dartssh2`.
///
/// Supports password and private key authentication.
class SftpProvider implements StorageProvider {
  SftpProvider({
    required this.profile,
    required this.password,
    this.privateKey,
  });

  @override
  final ConnectionProfile profile;

  /// Password for authentication (if auth method is password)
  final String? password;

  /// Private key content for authentication (if auth method is privateKey)
  final String? privateKey;

  SSHClient? _client;
  SftpClient? _sftp;
  bool _isConnected = false;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  String get displayName => 'SFTP: ${profile.name}';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  @override
  Future<void> connect() async {
    try {
      // Create SSH client
      if (profile.authMethod == AuthMethod.privateKey && privateKey != null) {
        _client = SSHClient(
          await SSHSocket.connect(
            profile.host!,
            profile.effectivePort,
            timeout: const Duration(seconds: 30),
          ),
          username: profile.username ?? '',
          identities: SSHKeyPair.fromPem(privateKey!),
        );
      } else {
        _client = SSHClient(
          await SSHSocket.connect(
            profile.host!,
            profile.effectivePort,
            timeout: const Duration(seconds: 30),
          ),
          username: profile.username ?? '',
          onPasswordRequest: () => password ?? '',
        );
      }

      // Create SFTP subsystem
      _sftp = await _client!.sftp();
      _isConnected = true;
      _connectionController.add(true);
    } catch (e) {
      _isConnected = false;
      throw StorageException(
        'SFTP connection failed: $e',
        code: StorageException.networkError,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    try {
      await _sftp?.close();
      _client?.close();
    } catch (_) {
      // Ignore errors during disconnect
    }
    _sftp = null;
    _client = null;

    if (!_connectionController.isClosed) {
      _connectionController.add(false);
      await _connectionController.close();
    }
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!_isConnected || _sftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final items = await _sftp!.listdir(path);
      final showHidden = options?.showHidden ?? false;

      return items
          .where((item) {
            // Skip . and .. entries
            if (item.filename == '.' || item.filename == '..') return false;
            // Filter hidden files
            if (!showHidden && HiddenEntryPolicy.isDotHidden(item.filename)) {
              return false;
            }
            return true;
          })
          .map((item) => _sftpItemToFileEntry(item, path))
          .toList();
    } catch (e) {
      throw StorageException(
        'SFTP list failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!_isConnected || _sftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final attrs = await _sftp!.stat(path);
      return FileEntry(
        name: basename(path),
        path: path,
        isDirectory: attrs.isDirectory,
        size: attrs.size ?? 0,
        modified: attrs.modifyTime != null
            ? DateTime.fromMillisecondsSinceEpoch(attrs.modifyTime! * 1000)
            : null,
        permissions: attrs.mode?.value != null
            ? _permissionsFromMode(attrs.mode!.value)
            : null,
        owner: attrs.userID?.toString(),
        group: attrs.groupID?.toString(),
        hidden: HiddenEntryPolicy.isDotHidden(basename(path)),
      );
    } catch (e) {
      throw StorageException(
        'SFTP stat failed: $e',
        code: StorageException.notFound,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  }) async* {
    if (!_isConnected || _sftp == null) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      final stat = await _sftp!.stat(path);
      final totalBytes = stat.size ?? 0;

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.inProgress,
        bytesTransferred: 0,
        totalBytes: totalBytes,
      );

      final file = await _sftp!.open(path);
      var bytesRead = 0;

      await for (final chunk in file.read()) {
        if (cancelToken?.isCancelled ?? false) {
          yield TransferProgress(
            operation: TransferOperation.read,
            state: TransferState.cancelled,
          );
          return;
        }
        bytesRead += chunk.length;
        yield TransferProgress(
          operation: TransferOperation.read,
          state: TransferState.inProgress,
          bytesTransferred: bytesRead,
          totalBytes: totalBytes,
        );
      }

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        bytesTransferred: bytesRead,
        totalBytes: totalBytes,
      );
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
    if (!_isConnected || _sftp == null) {
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      final file = await _sftp!.open(
        path,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      var bytesWritten = 0;

      await for (final chunk in data) {
        if (cancelToken?.isCancelled ?? false) {
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.cancelled,
          );
          return;
        }
        file.write(Stream.fromIterable([Uint8List.fromList(chunk)]));
        bytesWritten += chunk.length;
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.inProgress,
          bytesTransferred: bytesWritten,
        );
      }

      await file.close();

      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.completed,
        bytesTransferred: bytesWritten,
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
    // For same-provider copy, use SFTP rename/copy
    if (destProvider is SftpProvider && destProvider._sftp == _sftp) {
      try {
        // SFTP doesn't have native copy, so we need to read + write
        // For simplicity, use the generic approach
        final stat = await _sftp!.stat(sourcePath);
        if (stat.isDirectory) {
          // Directory copy - recursive
          yield* _copyDirectorySftp(
            sourcePath,
            destProvider,
            destPath,
            cancelToken,
          );
        } else {
          // File copy via read + write
          final totalBytes = stat.size ?? 0;
          var bytesTransferred = 0;

          final sourceFile = await _sftp!.open(sourcePath);
          final destFile = await destProvider._sftp!.open(
            destPath,
            mode:
                SftpFileOpenMode.write |
                SftpFileOpenMode.create |
                SftpFileOpenMode.truncate,
          );

          await for (final chunk in sourceFile.read()) {
            if (cancelToken?.isCancelled ?? false) {
              yield TransferProgress(
                operation: TransferOperation.copy,
                state: TransferState.cancelled,
              );
              return;
            }
            destFile.write(Stream.fromIterable([Uint8List.fromList(chunk)]));
            bytesTransferred += chunk.length;
            yield TransferProgress(
              operation: TransferOperation.copy,
              state: TransferState.inProgress,
              bytesTransferred: bytesTransferred,
              totalBytes: totalBytes,
            );
          }

          await destFile.close();

          yield TransferProgress(
            operation: TransferOperation.copy,
            state: TransferState.completed,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
          );
        }
      } catch (e) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.failed,
          error: e.toString(),
        );
      }
    } else {
      // Cross-provider: pipe read to write
      final totalBytes = (await stat(sourcePath)).size;
      var bytesTransferred = 0;

      final controller = StreamController<List<int>>();

      // Start reading
      final readStream = _sftp!.open(sourcePath).then((file) => file.read());
      readStream.then((stream) {
        stream.listen(
          (chunk) {
            bytesTransferred += chunk.length;
            controller.add(chunk);
          },
          onDone: () => controller.close(),
          onError: (Object e, [StackTrace? st]) => controller.addError(e, st),
        );
      });

      // Write to dest
      await for (final progress in destProvider.write(
        destPath,
        controller.stream,
        cancelToken: cancelToken,
      )) {
        if (progress.state == TransferState.inProgress) {
          yield progress.copyWith(
            operation: TransferOperation.copy,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
          );
        } else {
          yield progress.copyWith(operation: TransferOperation.copy);
        }
      }
    }
  }

  Stream<TransferProgress> _copyDirectorySftp(
    String sourcePath,
    SftpProvider destProvider,
    String destPath,
    CancelToken? cancelToken,
  ) async* {
    final entries = await list(sourcePath, const ListOptions(showHidden: true));
    var filesTransferred = 0;
    final totalFiles = entries.length;

    await destProvider.mkdir(destPath);

    for (final entry in entries) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.cancelled,
        );
        return;
      }

      final srcEntry = joinPath(sourcePath, entry.name);
      final destEntry = joinPath(destPath, entry.name);

      if (entry.isDirectory) {
        yield* _copyDirectorySftp(
          srcEntry,
          destProvider,
          destEntry,
          cancelToken,
        );
      } else {
        yield* copy(
          srcEntry,
          destProvider,
          destEntry,
          cancelToken: cancelToken,
        );
      }

      filesTransferred++;
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.inProgress,
        filesTransferred: filesTransferred,
        totalFiles: totalFiles,
      );
    }

    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.completed,
      filesTransferred: filesTransferred,
      totalFiles: totalFiles,
    );
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    if (!_isConnected || _sftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      await _sftp!.rename(sourcePath, destPath);
    } catch (e) {
      throw StorageException(
        'SFTP move failed: $e',
        code: StorageException.networkError,
        path: sourcePath,
        cause: e,
      );
    }
  }

  @override
  Future<void> rename(String path, String newName) async {
    final parent = dirname(path);
    final newPath = joinPath(parent, newName);
    await move(path, newPath);
  }

  @override
  Future<void> delete(String path) async {
    if (!_isConnected || _sftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final stat = await _sftp!.stat(path);
      if (stat.isDirectory) {
        // Recursively delete directory
        final entries = await _sftp!.listdir(path);
        for (final entry in entries) {
          if (entry.filename == '.' || entry.filename == '..') continue;
          await delete(joinPath(path, entry.filename));
        }
        await _sftp!.rmdir(path);
      } else {
        await _sftp!.remove(path);
      }
    } catch (e) {
      throw StorageException(
        'SFTP delete failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<void> mkdir(String path) async {
    if (!_isConnected || _sftp == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      await _sftp!.mkdir(path);
    } catch (e) {
      throw StorageException(
        'SFTP mkdir failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<bool> exists(String path) async {
    if (!_isConnected || _sftp == null) return false;
    try {
      await _sftp!.stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> get homePath async {
    return profile.defaultPath;
  }

  @override
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path) async => null;

  @override
  String normalizePath(String path) => p.normalize(path);

  @override
  String joinPath(String parent, String child) => p.join(parent, child);

  @override
  String basename(String path) => p.basename(path);

  @override
  String dirname(String path) => p.dirname(path);

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
      case ProviderCapability.streaming:
      case ProviderCapability.permissions:
      case ProviderCapability.search:
        return true;
      case ProviderCapability.freeSpace:
      case ProviderCapability.symlinks:
        return false;
    }
  }

  // ─── Private helpers ────────────────────────────────────────────

  FileEntry _sftpItemToFileEntry(SftpName item, String parentPath) {
    final isDir = item.attr.isDirectory;
    final name = item.filename;
    final fullPath = joinPath(parentPath, name);

    return FileEntry(
      name: name,
      path: fullPath,
      isDirectory: isDir,
      size: item.attr.size ?? 0,
      modified: item.attr.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
          : null,
      permissions: item.attr.mode?.value != null
          ? _permissionsFromMode(item.attr.mode!.value)
          : null,
      owner: item.attr.userID?.toString(),
      group: item.attr.groupID?.toString(),
      hidden: HiddenEntryPolicy.isDotHidden(name),
      symlink: item.attr.isSymbolicLink,
    );
  }

  String _permissionsFromMode(int mode) {
    final perms = StringBuffer();
    perms.write((mode & 256) != 0 ? 'r' : '-');
    perms.write((mode & 128) != 0 ? 'w' : '-');
    perms.write((mode & 64) != 0 ? 'x' : '-');
    perms.write((mode & 32) != 0 ? 'r' : '-');
    perms.write((mode & 16) != 0 ? 'w' : '-');
    perms.write((mode & 8) != 0 ? 'x' : '-');
    perms.write((mode & 4) != 0 ? 'r' : '-');
    perms.write((mode & 2) != 0 ? 'w' : '-');
    perms.write((mode & 1) != 0 ? 'x' : '-');
    return perms.toString();
  }
}
