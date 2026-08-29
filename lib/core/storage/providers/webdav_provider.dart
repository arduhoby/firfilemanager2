import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart' as dio;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:webdav_client/webdav_client.dart';

import '../models/connection_profile.dart';
import '../models/file_entry.dart';
import '../models/transfer_progress.dart';
import '../hidden_entry_policy.dart';
import '../storage_provider.dart';

/// A [StorageProvider] that connects to WebDAV servers using `webdav_client`.
class WebdavProvider implements StorageProvider {
  WebdavProvider({
    required this.profile,
    required this.password,
    int Function()? chunkSizeBytes,
  }) : _chunkSizeBytes = chunkSizeBytes ?? (() => uploadPartSize);

  /// Creates an already-connected provider for tests.
  WebdavProvider.withClient({
    required this.profile,
    required this.password,
    required Client client,
    int chunkSize = uploadPartSize,
  }) : assert(chunkSize > 0),
       _chunkSizeBytes = (() => chunkSize),
       _client = client,
       _isConnected = true;

  /// Cloudflare's free plan rejects requests larger than 100 MB. Leave a
  /// small margin so a part can always be uploaded in one WebDAV request.
  static const int uploadPartSize = 95 * 1024 * 1024;

  @override
  final ConnectionProfile profile;

  final String? password;

  final int Function() _chunkSizeBytes;
  int get _uploadPartSize => _chunkSizeBytes();

  Client? _client;
  bool _isConnected = false;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  String get displayName => 'WebDAV: ${profile.name}';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  @override
  Future<void> connect() async {
    try {
      final protocol = profile.effectivePort == 443 ? 'https' : 'http';
      final baseUrl = '$protocol://${profile.host}:${profile.effectivePort}';

      _client = newClient(
        baseUrl,
        user: profile.username ?? '',
        password: password ?? '',
      );

      // Test connection by listing root
      await _client!.readDir('/');
      _isConnected = true;
      _connectionController.add(true);
    } catch (e) {
      _isConnected = false;
      throw StorageException(
        'WebDAV connection failed: $e',
        code: StorageException.networkError,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _client = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
      await _connectionController.close();
    }
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!_isConnected || _client == null) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    try {
      final items = await _client!.readDir(path);
      final showHidden = options?.showHidden ?? false;

      return items
          .where((item) {
            final name = p.basename(item.path ?? '');
            if (name == '.' || name == '..') return false;
            if (!showHidden && HiddenEntryPolicy.isDotHidden(name)) {
              return false;
            }
            return true;
          })
          .map((item) {
            final name = p.basename(item.path ?? '');
            return FileEntry(
              name: name,
              path: item.path ?? '',
              isDirectory: item.isDir ?? false,
              size: item.size ?? 0,
              modified: item.mTime,
              hidden: HiddenEntryPolicy.isDotHidden(name),
            );
          })
          .toList();
    } catch (e) {
      throw StorageException(
        'WebDAV list failed: $e',
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
      final parent = p.dirname(path);
      final name = p.basename(path);
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
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException(
        'WebDAV stat failed: $e',
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

    io.Directory? tempDir;
    try {
      tempDir = await io.Directory.systemTemp.createTemp('webdav_download_');
      final tempFile = io.File('${tempDir.path}/combined_output');
      final parts = await _downloadParts(path);
      final totalBytes = parts.fold<int>(0, (total, part) => total + part.size);
      final entry = FileEntry(
        name: p.basename(path),
        path: path,
        isDirectory: false,
        size: totalBytes,
      );
      var bytesRead = 0;

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.inProgress,
        currentFile: entry,
        totalBytes: totalBytes,
      );

      final output = tempFile.openWrite();
      try {
        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
          final part = parts[partIndex];
          if (cancelToken?.isCancelled ?? false) {
            yield TransferProgress(
              operation: TransferOperation.read,
              state: TransferState.cancelled,
              currentFile: entry,
              bytesTransferred: bytesRead,
              totalBytes: totalBytes,
            );
            return;
          }
          final partFile = io.File(
            '${tempDir.path}/downloaded_part_$partIndex',
          );
          await _readRemoteFile(part.path, partFile.path, cancelToken);
          await _verifyDownloadedPart(part, partFile);
          await for (final bytes in partFile.openRead()) {
            if (cancelToken?.isCancelled ?? false) {
              yield TransferProgress(
                operation: TransferOperation.read,
                state: TransferState.cancelled,
                currentFile: entry,
                bytesTransferred: bytesRead,
                totalBytes: totalBytes,
              );
              return;
            }
            output.add(bytes);
            bytesRead += bytes.length;
            yield TransferProgress(
              operation: TransferOperation.read,
              state: TransferState.inProgress,
              currentFile: entry,
              bytesTransferred: bytesRead,
              totalBytes: totalBytes,
            );
          }
          await partFile.delete();
        }
        await output.flush();
      } finally {
        await output.close();
      }

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        currentFile: entry,
        bytesTransferred: bytesRead,
        totalBytes: totalBytes,
      );
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.read,
          state: TransferState.cancelled,
        );
        return;
      }
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: e.toString(),
      );
    } finally {
      if (tempDir != null) {
        await _deleteTempDirectory(tempDir);
      }
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

    io.Directory? tempDir;
    io.IOSink? activeSink;
    dio.CancelToken? activeRequest;
    final nonce = const Uuid().v4();
    final stagedFiles = <_WebdavTransactionFile>[];
    var bytesWritten = 0;
    var commitStarted = false;
    cancelToken?.onCancel(() => activeRequest?.cancel());

    try {
      tempDir = await io.Directory.systemTemp.createTemp('webdav_upload_');
      var partNumber = 1;
      var partBytes = 0;
      var chunked = false;
      var partFile = io.File('${tempDir.path}/part_$partNumber');
      var sink = partFile.openWrite();
      activeSink = sink;

      Future<void> closePart() async {
        await sink.flush();
        await sink.close();
        activeSink = null;
      }

      Future<void> stagePart() async {
        final finalPath = chunked ? _partPath(path, partNumber) : path;
        final stagingPath = _transactionPath(finalPath, 'upload', nonce);
        final requestToken = dio.CancelToken();
        activeRequest = requestToken;
        if (cancelToken?.isCancelled ?? false) requestToken.cancel();
        final stagedFile = _WebdavTransactionFile(
          originalPath: finalPath,
          transactionPath: stagingPath,
          localPath: partFile.path,
          size: await partFile.length(),
        );
        // Track it before starting the PUT: a cancelled/failed PUT may still
        // have created a partial object on some WebDAV servers.
        stagedFiles.add(stagedFile);
        try {
          await _client!.writeFromFile(
            partFile.path,
            stagingPath,
            cancelToken: requestToken,
          );
        } finally {
          if (identical(activeRequest, requestToken)) activeRequest = null;
        }
      }

      await for (final chunk in data) {
        if (cancelToken?.isCancelled ?? false) {
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.cancelled,
            bytesTransferred: bytesWritten,
          );
          return;
        }
        var offset = 0;
        while (offset < chunk.length) {
          if (partBytes == _uploadPartSize) {
            // Another byte proves the first full part is multipart.
            chunked = true;
            await closePart();
            await stagePart();
            partNumber++;
            if (partNumber > 9999) {
              throw StorageException(
                'WebDAV multipart upload exceeds the 9999-part limit',
                code: StorageException.notSupported,
                path: path,
              );
            }
            partBytes = 0;
            partFile = io.File('${tempDir.path}/part_$partNumber');
            sink = partFile.openWrite();
            activeSink = sink;
          }

          final remaining = _uploadPartSize - partBytes;
          final count = (chunk.length - offset).clamp(0, remaining).toInt();
          sink.add(chunk.sublist(offset, offset + count));
          offset += count;
          partBytes += count;
          bytesWritten += count;
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.inProgress,
            bytesTransferred: bytesWritten,
          );
        }
      }

      await closePart();
      await stagePart();
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
          bytesTransferred: bytesWritten,
        );
        return;
      }

      final oldFiles = await _existingFamily(path);
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
          bytesTransferred: bytesWritten,
        );
        return;
      }

      // From the first remote MOVE onward cancellation is intentionally
      // ignored: the commit either publishes the new family or restores it.
      commitStarted = true;
      await _commitStagedUpload(path, stagedFiles, oldFiles, nonce);
      await _verifyPublishedUpload(stagedFiles);
      stagedFiles.clear();
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.completed,
        bytesTransferred: bytesWritten,
      );
    } catch (e) {
      if (!commitStarted && (cancelToken?.isCancelled ?? false)) {
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
          bytesTransferred: bytesWritten,
        );
        return;
      }
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: e.toString(),
      );
    } finally {
      try {
        await activeSink?.close();
      } catch (_) {
        // Preserve the transfer result if closing a failed sink also fails.
      }
      await _removeRemoteBestEffort(
        stagedFiles.map((file) => file.transactionPath),
      );
      if (tempDir != null) await _deleteTempDirectory(tempDir);
    }
  }

  /// Resolves a logical path to either the ordinary file or its ordered
  /// multipart siblings. A missing or non-contiguous part is treated as an
  /// incomplete upload instead of silently producing a corrupt file.
  Future<List<_WebdavPart>> _downloadParts(String path) async {
    final parent = p.dirname(path);
    final requestedName = p.basename(path);
    final selectedPart = RegExp(
      r'^(.*)\.part(\d{4})$',
    ).firstMatch(requestedName);
    final name = selectedPart?.group(1) ?? requestedName;
    final partPattern = RegExp(
      '^${RegExp.escape(name)}\\.part(\\d{4})'
      r'$',
    );
    final entries = await _client!.readDir(parent);
    final parts = <_WebdavPart>[];

    for (final entry in entries) {
      final entryName = p.basename(entry.path ?? '');
      final match = partPattern.firstMatch(entryName);
      if (match == null || entry.isDir == true) continue;
      parts.add(
        _WebdavPart(
          path: entry.path ?? p.join(parent, entryName),
          number: int.parse(match.group(1)!),
          size: entry.size ?? 0,
        ),
      );
    }

    final ordinaryFile = entries.where(
      (entry) => p.basename(entry.path ?? '') == name && entry.isDir != true,
    );
    if (ordinaryFile.isNotEmpty) {
      return [
        _WebdavPart(
          path: ordinaryFile.first.path ?? path,
          number: 0,
          size: ordinaryFile.first.size ?? 0,
        ),
      ];
    }
    if (parts.isEmpty) {
      return [_WebdavPart(path: path, number: 0, size: 0)];
    }
    if (parts.length < 2) {
      throw StorageException(
        'WebDAV multipart upload is incomplete for $path',
        code: StorageException.notFound,
        path: path,
      );
    }
    parts.sort((a, b) => a.number.compareTo(b.number));
    for (var index = 0; index < parts.length; index++) {
      if (parts[index].number != index + 1 ||
          (index < parts.length - 1 && parts[index].size != _uploadPartSize) ||
          (index == parts.length - 1 &&
              (parts[index].size <= 0 ||
                  parts[index].size > _uploadPartSize))) {
        throw StorageException(
          'WebDAV multipart upload is incomplete for $path',
          code: StorageException.notFound,
          path: path,
        );
      }
    }
    return parts;
  }

  String _partPath(String path, int partNumber) =>
      '$path.part${partNumber.toString().padLeft(4, '0')}';

  String _transactionPath(String path, String kind, String nonce) {
    final parent = p.dirname(path);
    final name = p.basename(path);
    return p.join(parent, '.$name.webdav-$kind-$nonce');
  }

  Future<void> _commitStagedUpload(
    String path,
    List<_WebdavTransactionFile> stagedFiles,
    List<String> oldFiles,
    String nonce,
  ) async {
    final backups =
        oldFiles
            .map(
              (oldPath) => _WebdavTransactionFile(
                originalPath: oldPath,
                transactionPath: _transactionPath(oldPath, 'backup', nonce),
                localPath: '',
                size: 0,
              ),
            )
            .toList()
          ..sort((a, b) {
            final aPart = _partNumber(a.originalPath);
            final bPart = _partNumber(b.originalPath);
            if (aPart == 0 && bPart != 0) return 1;
            if (aPart != 0 && bPart == 0) return -1;
            return aPart.compareTo(bPart);
          });
    final movedBackups = <_WebdavTransactionFile>[];
    final published = <_WebdavTransactionFile>[];

    try {
      for (final backup in backups) {
        // Record before MOVE because the server may complete it even if the
        // response times out. Rollback then attempts restoration.
        movedBackups.add(backup);
        await _client!.rename(
          backup.originalPath,
          backup.transactionPath,
          false,
        );
      }
      final publishOrder = stagedFiles.toList()
        ..sort(
          (a, b) => _partNumber(
            b.originalPath,
          ).compareTo(_partNumber(a.originalPath)),
        );
      for (final staged in publishOrder) {
        // DELETE is idempotent if this MOVE never reached the server.
        published.add(staged);
        try {
          await _client!.rename(
            staged.transactionPath,
            staged.originalPath,
            false,
          );
        } catch (_) {
          // Some Cloudflare-backed WebDAV servers accept PUT but reject MOVE.
          // Upload the already-buffered part directly to its final name.
          await _client!.writeFromFile(
            staged.localPath,
            staged.originalPath,
            cancelToken: dio.CancelToken(),
          );
          await _removeRemoteBestEffort([staged.transactionPath]);
        }
      }
    } catch (error) {
      var rollbackComplete = true;
      for (final publishedFile in published) {
        try {
          await _client!.remove(publishedFile.originalPath);
        } catch (_) {
          rollbackComplete = false;
        }
      }
      final restoreOrder = movedBackups.toList()
        ..sort((a, b) {
          final aPart = _partNumber(a.originalPath);
          final bPart = _partNumber(b.originalPath);
          if (aPart == 0 && bPart != 0) return -1;
          if (aPart != 0 && bPart == 0) return 1;
          return bPart.compareTo(aPart);
        });
      for (final backup in restoreOrder) {
        try {
          await _client!.rename(
            backup.transactionPath,
            backup.originalPath,
            false,
          );
        } catch (_) {
          rollbackComplete = false;
        }
      }
      if (!rollbackComplete) {
        throw StorageException(
          'WebDAV upload commit failed and rollback is incomplete: $error',
          code: StorageException.networkError,
          path: path,
          cause: error,
        );
      }
      throw StorageException(
        'WebDAV upload commit failed; previous file was restored: $error',
        code: StorageException.networkError,
        path: path,
        cause: error,
      );
    }

    await _removeRemoteBestEffort(
      backups.map((backup) => backup.transactionPath),
    );
  }

  Future<void> _verifyPublishedUpload(
    List<_WebdavTransactionFile> files,
  ) async {
    if (files.isEmpty) return;
    final parent = p.dirname(files.first.originalPath);
    final entries = await _client!.readDir(parent);
    for (final file in files) {
      final name = p.basename(file.originalPath);
      final matches = entries.where(
        (entry) => entry.isDir != true && p.basename(entry.path ?? '') == name,
      );
      if (matches.isEmpty ||
          (matches.first.size != null && matches.first.size != file.size)) {
        throw StorageException(
          'WebDAV part upload could not be verified: $name',
          code: StorageException.networkError,
          path: file.originalPath,
        );
      }
    }
  }

  Future<List<String>> _existingFamily(String path) async {
    final parent = p.dirname(path);
    final name = p.basename(path);
    final pattern = RegExp(
      '^${RegExp.escape(name)}(?:\\.part\\d{4})?'
      r'$',
    );
    final entries = await _client!.readDir(parent);
    return entries
        .where(
          (entry) =>
              entry.isDir != true &&
              pattern.hasMatch(p.basename(entry.path ?? '')),
        )
        .map(
          (entry) => entry.path ?? p.join(parent, p.basename(entry.path ?? '')),
        )
        .toList();
  }

  int _partNumber(String path) {
    final match = RegExp(r'\.part(\d{4})$').firstMatch(p.basename(path));
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  Future<void> _removeRemoteBestEffort(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await _client?.remove(path);
      } catch (_) {
        // Cleanup is intentionally best-effort.
      }
    }
  }

  Future<void> _readRemoteFile(
    String remotePath,
    String localPath,
    CancelToken? cancelToken,
  ) async {
    final requestCancelToken = dio.CancelToken();
    cancelToken?.onCancel(requestCancelToken.cancel);
    if (cancelToken?.isCancelled ?? false) requestCancelToken.cancel();
    await _client!.read2File(
      remotePath,
      localPath,
      cancelToken: requestCancelToken,
    );
  }

  Future<void> _verifyDownloadedPart(
    _WebdavPart part,
    io.File localFile,
  ) async {
    if (part.size <= 0) return;
    final actualSize = await localFile.length();
    if (actualSize != part.size) {
      throw StorageException(
        'WebDAV part size changed while downloading ${part.path}',
        code: StorageException.networkError,
        path: part.path,
      );
    }
  }

  Future<void> _deleteTempDirectory(io.Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A failed cleanup must not hide the transfer result.
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
    io.Directory? tempDir;
    try {
      if (!_isConnected || _client == null) {
        throw StorageException(
          'Not connected',
          code: StorageException.networkError,
        );
      }
      tempDir = await io.Directory.systemTemp.createTemp('webdav_copy_');
      final tempFile = io.File('${tempDir.path}/combined_output');
      final parts = await _downloadParts(sourcePath);
      var bytesTransferred = 0;
      final output = tempFile.openWrite();
      try {
        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
          final part = parts[partIndex];
          if (cancelToken?.isCancelled ?? false) {
            yield TransferProgress(
              operation: TransferOperation.copy,
              state: TransferState.cancelled,
              bytesTransferred: bytesTransferred,
            );
            return;
          }
          final partFile = io.File(
            '${tempDir.path}/downloaded_part_$partIndex',
          );
          await _readRemoteFile(part.path, partFile.path, cancelToken);
          await _verifyDownloadedPart(part, partFile);
          await for (final bytes in partFile.openRead()) {
            if (cancelToken?.isCancelled ?? false) {
              yield TransferProgress(
                operation: TransferOperation.copy,
                state: TransferState.cancelled,
                bytesTransferred: bytesTransferred,
              );
              return;
            }
            output.add(bytes);
            bytesTransferred += bytes.length;
          }
          await partFile.delete();
        }
        await output.flush();
      } finally {
        await output.close();
      }

      await for (final progress in destProvider.write(
        destPath,
        tempFile.openRead(),
        cancelToken: cancelToken,
      )) {
        yield progress.copyWith(
          operation: TransferOperation.copy,
          totalBytes: bytesTransferred,
        );
      }
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.cancelled,
        );
        return;
      }
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.failed,
        error: e.toString(),
      );
    } finally {
      if (tempDir != null) {
        await _deleteTempDirectory(tempDir);
      }
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
      await _client!.rename(sourcePath, destPath, false);
    } catch (e) {
      throw StorageException(
        'WebDAV move failed: $e',
        code: StorageException.networkError,
        path: sourcePath,
        cause: e,
      );
    }
  }

  @override
  Future<void> rename(String path, String newName) async {
    final parent = p.dirname(path);
    final newPath = p.join(parent, newName);
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
      await _client!.remove(path);
    } catch (e) {
      throw StorageException(
        'WebDAV delete failed: $e',
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
      await _client!.mkdir(path);
    } catch (e) {
      throw StorageException(
        'WebDAV mkdir failed: $e',
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

class _WebdavPart {
  const _WebdavPart({
    required this.path,
    required this.number,
    required this.size,
  });

  final String path;
  final int number;
  final int size;
}

class _WebdavTransactionFile {
  const _WebdavTransactionFile({
    required this.originalPath,
    required this.transactionPath,
    required this.localPath,
    required this.size,
  });

  final String originalPath;
  final String transactionPath;
  final String localPath;
  final int size;
}
