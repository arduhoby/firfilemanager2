import 'dart:async';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart';

import '../../models/connection_profile.dart';
import '../../models/file_entry.dart';
import '../../models/transfer_progress.dart';
import '../../hidden_entry_policy.dart';
import '../../storage_provider.dart';

class NextcloudProvider implements StorageProvider {
  NextcloudProvider(this.profile, {this.password});

  @override
  final ConnectionProfile profile;

  final String? password;

  Client? _client;
  bool _isConnected = false;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  String get displayName => 'Nextcloud: ${profile.name}';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  @override
  Future<void> connect() async {
    try {
      final protocol = profile.effectivePort == 443 ? 'https' : 'http';
      var host = profile.host ?? '';
      if (host.startsWith('http://')) host = host.substring(7);
      if (host.startsWith('https://')) host = host.substring(8);
      // Strip trailing slash if present
      final cleanHost = host.endsWith('/')
          ? host.substring(0, host.length - 1)
          : host;

      final portSuffix = (profile.port != null) ? ':${profile.port}' : '';
      final username = profile.username ?? '';
      final encodedUsername = Uri.encodeComponent(username);

      if (username.isEmpty) {
        throw Exception(
          'Kullanıcı adı gerekli (Username is required for Nextcloud)',
        );
      }

      // Modern Nextcloud WebDAV URL: /remote.php/dav/files/USERNAME/
      final baseUrl =
          '$protocol://$cleanHost$portSuffix/remote.php/dav/files/$encodedUsername';

      if (profile.authMethod == AuthMethod.password) {
        if (password == null || password!.isEmpty) {
          throw Exception(
            'Şifre gerekli (Password is required for Basic Auth)',
          );
        }
        _client = newClient(baseUrl, user: username, password: password ?? '');
      } else {
        throw Exception(
          'Nextcloud OAuth is not fully implemented yet. Please use Basic Auth (username/password).',
        );
      }

      // Test connection
      await _client!.readDir('/');
      _isConnected = true;
      _connectionController.add(true);
    } catch (e, stack) {
      _isConnected = false;

      // Fallback: Try legacy WebDAV endpoint
      try {
        final protocol = profile.effectivePort == 443 ? 'https' : 'http';
        var host = profile.host ?? '';
        if (host.startsWith('http://')) host = host.substring(7);
        if (host.startsWith('https://')) host = host.substring(8);
        final cleanHost = host.endsWith('/')
            ? host.substring(0, host.length - 1)
            : host;
        final portSuffix = (profile.port != null) ? ':${profile.port}' : '';

        final legacyBaseUrl =
            '$protocol://$cleanHost$portSuffix/remote.php/webdav';

        _client = newClient(
          legacyBaseUrl,
          user: profile.username ?? '',
          password: password ?? '',
        );
        await _client!.readDir('/');
        _isConnected = true;
        _connectionController.add(true);
        return;
      } catch (fallbackError) {
        throw StorageException(
          'Nextcloud connection failed. Modern error: $e. Legacy error: $fallbackError',
          cause: fallbackError,
        );
      }
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
    if (!_isConnected || _client == null)
      throw StorageException('Not connected');

    try {
      final items = await _client!.readDir(path);
      final showHidden = options?.showHidden ?? false;

      return items
          .where((item) {
            final name = p.basename(item.path ?? '');
            if (name == '.' || name == '..') return false;
            if (!showHidden && HiddenEntryPolicy.isDotHidden(name))
              return false;
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
      throw StorageException('Nextcloud list failed: $e', cause: e);
    }
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!_isConnected || _client == null)
      throw StorageException('Not connected');

    try {
      final parent = p.dirname(path);
      final name = p.basename(path);
      final entries = await list(parent);
      final entry = entries.where((e) => e.name == name).firstOrNull;
      if (entry == null) {
        throw StorageException('Not found', code: StorageException.notFound);
      }
      return entry;
    } catch (e) {
      if (e is StorageException) rethrow;
      throw StorageException('Nextcloud stat failed: $e', cause: e);
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
      final tempDir = await io.Directory.systemTemp.createTemp('nc_download_');
      final tempFile = io.File('${tempDir.path}/${p.basename(path)}');

      await _client!.read2File(path, tempFile.path);

      final bytes = tempFile.readAsBytesSync();
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        bytesTransferred: bytes.length,
        totalBytes: bytes.length,
      );

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
    if (!_isConnected || _client == null) {
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.failed,
        error: 'Not connected',
      );
      return;
    }

    try {
      final tempDir = await io.Directory.systemTemp.createTemp('nc_upload_');
      final tempFile = io.File('${tempDir.path}/${p.basename(path)}');

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
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.inProgress,
          bytesTransferred: bytesWritten,
        );
      }

      await sink.flush();
      await sink.close();

      await _client!.writeFromFile(tempFile.path, path);

      tempFile.deleteSync();
      tempDir.deleteSync();

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
    final controller = StreamController<List<int>>();
    var bytesTransferred = 0;

    try {
      final tempDir = await io.Directory.systemTemp.createTemp('nc_copy_');
      final tempFile = io.File('${tempDir.path}/${p.basename(sourcePath)}');

      await _client!.read2File(sourcePath, tempFile.path);
      final bytes = tempFile.readAsBytesSync();
      bytesTransferred = bytes.length;

      controller.add(bytes);
      controller.close();

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
    if (!_isConnected || _client == null)
      throw StorageException('Not connected');
    try {
      await _client!.rename(sourcePath, destPath, false);
    } catch (e) {
      throw StorageException('Nextcloud move failed: $e', cause: e);
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
    if (!_isConnected || _client == null)
      throw StorageException('Not connected');
    try {
      await _client!.remove(path);
    } catch (e) {
      throw StorageException('Nextcloud delete failed: $e', cause: e);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    if (!_isConnected || _client == null)
      throw StorageException('Not connected');
    try {
      await _client!.mkdir(path);
    } catch (e) {
      throw StorageException('Nextcloud mkdir failed: $e', cause: e);
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
          } catch (_) {}
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
