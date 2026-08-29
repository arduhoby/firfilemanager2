import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:smb_connect/smb_connect.dart';

import '../models/connection_profile.dart';
import '../models/file_entry.dart';
import '../models/transfer_progress.dart';
import '../hidden_entry_policy.dart';
import '../storage_provider.dart';

/// A [StorageProvider] that connects to SMB shares using `smb_connect`.
class SmbProvider implements StorageProvider {
  SmbProvider({required this.profile, required this.password})
    : _isConnected = false;

  SmbProvider.withClient({
    required this.profile,
    required this.password,
    required SmbConnect client,
  }) : _client = client,
       _isConnected = true;

  @override
  final ConnectionProfile profile;

  final String? password;

  SmbConnect? _client;
  bool _isConnected;
  Future<void> _operationTail = Future<void>.value();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  String get displayName => 'SMB: ${profile.name}';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  @override
  Future<void> connect() async {
    try {
      final host = profile.host ?? 'localhost';
      final username = profile.username ?? '';
      final pass = password ?? '';

      _client = await SmbConnect.connectAuth(
        host: host,
        username: username,
        password: pass,
        domain: '',
      );

      _isConnected = true;
      _connectionController.add(true);
    } catch (e) {
      _isConnected = false;
      _client = null;
      throw StorageException(
        'SMB connection failed: $e',
        code: StorageException.networkError,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() => _runSerialized(_disconnect);

  Future<void> _disconnect() async {
    _isConnected = false;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;

    if (!_connectionController.isClosed) {
      _connectionController.add(false);
      await _connectionController.close();
    }
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) =>
      _runSerialized(() => _list(path, options));

  Future<List<FileEntry>> _list(String path, [ListOptions? options]) async {
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      // smb_connect expects POSIX-style paths even when the Flutter app runs
      // on Windows. Keep the share/folder path stable across platforms.
      path = normalizePath(path);
      final showHidden = options?.showHidden ?? false;

      // SMB paths normally start with share names.
      // If path is root '/', we show available shares.
      if (path == '/' || path == '') {
        final shares = await _client!.listShares();
        return shares
            .map(
              (share) => FileEntry(
                name: share.name,
                path: '/${share.name}',
                isDirectory: true,
                size: 0,
                hidden: false,
              ),
            )
            .toList();
      }

      final folder = await _client!.file(path);
      final list = await _client!.listFiles(folder);

      return list
          .where((item) {
            if (item.name == '.' || item.name == '..') return false;
            if (!showHidden &&
                HiddenEntryPolicy.isHidden(
                  item.name,
                  hasPlatformHiddenAttribute: item.isHidden(),
                )) {
              return false;
            }
            return true;
          })
          .map(
            (item) => FileEntry(
              name: item.name,
              path: joinPath(path, item.name),
              isDirectory: item.isDirectory(),
              size: item.isDirectory() ? 0 : item.size,
              modified: DateTime.fromMillisecondsSinceEpoch(item.lastModified),
              hidden: item.isHidden(),
            ),
          )
          .toList();
    } catch (e) {
      throw StorageException(
        'SMB listing failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      if (path == '/' || path == '') {
        return FileEntry(name: 'Root', path: '/', isDirectory: true);
      }

      final file = await _client!.file(path);
      return FileEntry(
        name: file.name,
        path: path,
        isDirectory: file.isDirectory(),
        size: file.isDirectory() ? 0 : file.size,
        modified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        hidden: file.isHidden(),
      );
    } catch (e) {
      throw StorageException(
        'SMB stat failed: $e',
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
    if (!_isConnected || _client == null) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      final file = await _client!.file(path);
      final totalBytes = file.size;
      final entry = await stat(path);
      var bytesRead = 0;

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.inProgress,
        currentFile: entry,
        bytesTransferred: 0,
        totalBytes: totalBytes,
      );

      final stream = await _client!.openRead(file);
      await for (final chunk in stream) {
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
          currentFile: entry,
          bytesTransferred: bytesRead,
          totalBytes: totalBytes,
        );
      }

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        currentFile: entry,
        bytesTransferred: totalBytes,
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
    if (!_isConnected || _client == null) {
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    final parent = dirname(path);
    final name = basename(path);
    final destinationExists = await exists(path);
    final token = DateTime.now().microsecondsSinceEpoch;
    final stagingPath = destinationExists
        ? joinPath(parent, '.$name.fir-part-$token')
        : path;
    final backupPath = joinPath(parent, '.$name.fir-backup-$token');
    var originalMoved = false;
    var stagingMoved = false;
    try {
      final stagingFile = await _client!.createFile(stagingPath);
      final sink = await _client!.openWrite(stagingFile);
      var bytesWritten = 0;

      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.inProgress,
        bytesTransferred: 0,
      );

      await for (final chunk in data) {
        if (cancelToken?.isCancelled ?? false) {
          await sink.close();
          if (await exists(stagingPath)) await delete(stagingPath);
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.cancelled,
            bytesTransferred: bytesWritten,
          );
          return;
        }
        sink.add(chunk);
        bytesWritten += chunk.length;
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.inProgress,
          bytesTransferred: bytesWritten,
        );
      }

      await sink.flush();
      await sink.close();

      if (!destinationExists) {
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.completed,
          bytesTransferred: bytesWritten,
        );
        return;
      }

      await move(path, backupPath);
      originalMoved = true;
      try {
        await move(stagingPath, path);
        stagingMoved = true;
      } catch (_) {
        if (originalMoved && await exists(backupPath)) {
          await move(backupPath, path);
          originalMoved = false;
        }
        rethrow;
      }

      if (originalMoved) {
        await delete(backupPath);
        originalMoved = false;
      }

      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.completed,
        bytesTransferred: bytesWritten,
      );
    } catch (error) {
      try {
        if (!stagingMoved && await exists(stagingPath)) {
          await delete(stagingPath);
        }
        if (originalMoved && !await exists(path) && await exists(backupPath)) {
          await move(backupPath, path);
        }
      } catch (_) {
        // Preserve the original transfer error; recovery is best effort.
      }
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: error.toString(),
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
    if (!_isConnected || _client == null) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      final sourceEntry = await stat(sourcePath);
      if (sourceEntry.isDirectory) {
        yield* _copyDirectory(
          sourcePath,
          destProvider,
          destPath,
          options,
          cancelToken,
        );
      } else {
        final totalBytes = sourceEntry.size;
        var bytesTransferred = 0;

        final file = await _client!.file(sourcePath);
        final readStream = await _client!.openRead(file);

        final controller = StreamController<List<int>>();

        readStream.listen(
          (chunk) {
            bytesTransferred += chunk.length;
            controller.add(chunk);
          },
          onDone: () => controller.close(),
          onError: (Object e, [StackTrace? st]) => controller.addError(e, st),
        );

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
          } else if (progress.state == TransferState.completed) {
            yield progress.copyWith(
              operation: TransferOperation.copy,
              bytesTransferred: totalBytes,
              totalBytes: totalBytes,
            );
          } else {
            yield progress.copyWith(operation: TransferOperation.copy);
          }
        }
      }
    } catch (e) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.failed,
        error: e.toString(),
      );
    }
  }

  Stream<TransferProgress> _copyDirectory(
    String sourcePath,
    StorageProvider destProvider,
    String destPath,
    CopyOptions options,
    CancelToken? cancelToken,
  ) async* {
    final entries = await list(sourcePath, const ListOptions(showHidden: true));
    await destProvider.mkdir(destPath);

    for (final entry in entries) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.cancelled,
        );
        return;
      }

      final nextDestPath = destProvider.joinPath(destPath, entry.name);
      yield* copy(
        entry.path,
        destProvider,
        nextDestPath,
        options: options,
        cancelToken: cancelToken,
      );
    }
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final file = await _client!.file(sourcePath);
      await _client!.rename(file, destPath);
    } catch (e) {
      throw StorageException(
        'SMB move failed: $e',
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
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final file = await _client!.file(path);
      await _client!.delete(file);
    } catch (e) {
      throw StorageException(
        'SMB delete failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<void> mkdir(String path) async {
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      await _client!.createFolder(path);
    } catch (e) {
      throw StorageException(
        'SMB mkdir failed: $e',
        code: StorageException.networkError,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<bool> exists(String path) async {
    if (!_isConnected || _client == null) return false;
    try {
      final file = await _client!.file(path);
      return file.isExists;
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
    var cleaned = path.replaceAll('\\', '/');
    if (!cleaned.startsWith('/')) {
      cleaned = '/$cleaned';
    }
    return cleaned;
  }

  @override
  String joinPath(String parent, String child) {
    if (parent == '/') return '/$child';
    return p.join(parent, child).replaceAll('\\', '/');
  }

  @override
  String basename(String path) => p.basename(path);

  @override
  String dirname(String path) => p.dirname(path).replaceAll('\\', '/');

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
      case ProviderCapability.search:
        return true;
      case ProviderCapability.freeSpace:
      case ProviderCapability.symlinks:
      case ProviderCapability.permissions:
        return false;
    }
  }
}
