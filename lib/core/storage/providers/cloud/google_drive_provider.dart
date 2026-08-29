import 'dart:async';
import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../env.dart';
import '../../storage_provider.dart';
import '../../models/connection_profile.dart';
import '../../models/file_entry.dart';
import '../../models/transfer_progress.dart';

class GoogleDriveProvider implements StorageProvider {
  final ConnectionProfile profile;
  final String? clientId;
  final String? clientSecret;
  drive.DriveApi? _api;

  GoogleDriveProvider({required this.profile, this.clientId, this.clientSecret});

  @override
  String get displayName => profile.name;

  @override
  bool get isConnected => _api != null;

  @override
  Stream<bool> get connectionStateChanges => const Stream.empty();

  @override
  Future<void> connect() async {
    final effectiveClientId = (clientId ?? Env.googleDriveClientId).trim();
    if (!_isConfiguredValue(effectiveClientId) ||
        !effectiveClientId.endsWith('.apps.googleusercontent.com')) {
      throw StorageException(
        'Google Drive OAuth yapılandırılmamış. Ayarlar > Bulut Servisleri '
        'API Anahtarları bölümüne Google Cloud Console\'da "Desktop app" '
        'türünde oluşturulan Client ID\'yi girin.',
      );
    }

    final rawClientSecret = (clientSecret ?? Env.googleDriveClientSecret).trim();
    final effectiveClientSecret = _isConfiguredValue(rawClientSecret)
        ? rawClientSecret
        : null;

    try {
      final id = ClientId(effectiveClientId, effectiveClientSecret);
      final scopes = [drive.DriveApi.driveScope];

      final authClient = await clientViaUserConsent(id, scopes, (url) async {
        final uri = Uri.parse(url);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          throw Exception('Could not launch Google Sign In URL: $e');
        }
      });
      _api = drive.DriveApi(authClient);
    } catch (e, st) {
      print('Google Drive Connection Error: $e\n$st');
      throw StorageException('Failed to connect to Google Drive: $e');
    }
  }

  static bool _isConfiguredValue(String value) {
    if (value.isEmpty) return false;
    final normalized = value.toUpperCase();
    return !normalized.startsWith('YOUR_') &&
        !normalized.contains('PLACEHOLDER') &&
        !normalized.contains('TODO');
  }

  @override
  Future<void> disconnect() async {
    _api = null;
  }

  String _resolveId(String path) {
    if (path == '/' || path.isEmpty) return 'root';
    return path;
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    _checkConnection();
    final parentId = _resolveId(path);

    final fileList = await _api!.files.list(
      q: "'$parentId' in parents and trashed = false",
      $fields: 'files(id, name, mimeType, size, modifiedTime)',
    );

    final items = <FileEntry>[];
    for (final f in fileList.files ?? <drive.File>[]) {
      final isDir = f.mimeType == 'application/vnd.google-apps.folder';
      items.add(
        FileEntry(
          name: f.name ?? 'unknown',
          path: f.id ?? '',
          isDirectory: isDir,
          size: f.size != null ? int.tryParse(f.size!) ?? 0 : 0,
          modified: f.modifiedTime ?? DateTime.now(),
          permissions: '',
        ),
      );
    }
    return items;
  }

  @override
  Future<FileEntry> stat(String path) async {
    _checkConnection();
    final id = _resolveId(path);
    if (id == 'root') {
      return FileEntry(
        name: 'root',
        path: 'root',
        isDirectory: true,
        size: 0,
        modified: DateTime.now(),
        permissions: '',
      );
    }
    final f =
        await _api!.files.get(
              id,
              $fields: 'id, name, mimeType, size, modifiedTime',
            )
            as drive.File;
    final isDir = f.mimeType == 'application/vnd.google-apps.folder';
    return FileEntry(
      name: f.name ?? 'unknown',
      path: f.id ?? '',
      isDirectory: isDir,
      size: f.size != null ? int.tryParse(f.size!) ?? 0 : 0,
      modified: f.modifiedTime ?? DateTime.now(),
      permissions: '',
    );
  }

  @override
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  }) async* {
    _checkConnection();
    final id = _resolveId(path);

    yield TransferProgress(
      operation: TransferOperation.read,
      state: TransferState.inProgress,
    );

    try {
      final media =
          await _api!.files.get(
                id,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;
      final totalBytes = media.length ?? 0;
      var bytesTransferred = 0;

      await for (final chunk in media.stream) {
        if (cancelToken?.isCancelled ?? false) {
          yield TransferProgress(
            operation: TransferOperation.read,
            state: TransferState.cancelled,
          );
          return;
        }
        bytesTransferred += chunk.length;
        yield TransferProgress(
          operation: TransferOperation.read,
          state: TransferState.inProgress,
          bytesTransferred: bytesTransferred,
          totalBytes: totalBytes,
        );
      }

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.completed,
        bytesTransferred: bytesTransferred,
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
    _checkConnection();
    // Complex to implement cleanly without parent ID.
    throw UnimplementedError(
      'Write requires file metadata which is not provided by standard write(path, stream)',
    );
  }

  @override
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options = const CopyOptions(),
    CancelToken? cancelToken,
  }) async* {
    _checkConnection();

    try {
      final sourceEntry = await stat(sourcePath);
      final totalBytes = sourceEntry.size;
      var bytesTransferred = 0;

      if (sourceEntry.isDirectory) {
        yield* _copyDirectory(
          sourcePath,
          destProvider,
          destPath,
          options,
          cancelToken,
        );
      } else {
        // If same provider, use native Google Drive copy
        if (destProvider is GoogleDriveProvider &&
            destProvider.profile.id == profile.id) {
          yield TransferProgress(
            operation: TransferOperation.copy,
            state: TransferState.inProgress,
            bytesTransferred: 0,
            totalBytes: totalBytes,
          );

          final file = drive.File();
          final parentId = destProvider._resolveId(
            destProvider.dirname(destPath),
          );
          file.parents = [parentId];
          file.name = destProvider.basename(destPath);

          await _api!.files.copy(file, sourcePath);

          yield TransferProgress(
            operation: TransferOperation.copy,
            state: TransferState.completed,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
          );
          return;
        }

        // Cross-provider copy:
        final id = _resolveId(sourcePath);
        final media =
            await _api!.files.get(
                  id,
                  downloadOptions: drive.DownloadOptions.fullMedia,
                )
                as drive.Media;

        final controller = StreamController<List<int>>();

        media.stream.listen(
          (chunk) {
            bytesTransferred += chunk.length;
            controller.add(chunk);
          },
          onDone: () => controller.close(),
          onError: (Object e) => controller.addError(e),
          cancelOnError: true,
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
    var filesTransferred = 0;
    final totalFiles = entries.length;

    await destProvider.mkdir(destPath);

    for (final entry in entries) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.cancelled,
          filesTransferred: filesTransferred,
          totalFiles: totalFiles,
        );
        return;
      }

      final srcEntry = entry.path;
      final destEntry = destProvider.joinPath(destPath, entry.name);

      if (entry.isDirectory) {
        yield* _copyDirectory(
          srcEntry,
          destProvider,
          destEntry,
          options,
          cancelToken,
        );
      } else {
        yield* copy(
          srcEntry,
          destProvider,
          destEntry,
          options: options,
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
  Future<void> delete(String path) async {
    _checkConnection();
    final id = _resolveId(path);
    await _api!.files.delete(id);
  }

  @override
  Future<void> rename(String oldPath, String newName) async {
    _checkConnection();
    final id = _resolveId(oldPath);
    final file = drive.File()..name = newName;
    await _api!.files.update(file, id);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnimplementedError();
  }

  @override
  Future<void> mkdir(String path) async {
    _checkConnection();
    throw UnimplementedError();
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path) async => null;

  @override
  Future<String> get homePath async => 'root';

  @override
  String normalizePath(String path) => path;

  @override
  String joinPath(String parent, String child) => child;

  @override
  String basename(String path) => path;

  @override
  String dirname(String path) => 'root';

  @override
  Future<List<FileEntry>> search(
    String path,
    String query, {
    bool recursive = false,
  }) async {
    _checkConnection();
    final gQuery = "name contains '$query' and trashed = false";

    final fileList = await _api!.files.list(
      q: gQuery,
      $fields: 'files(id, name, mimeType, size, modifiedTime)',
    );

    final items = <FileEntry>[];
    for (final f in fileList.files ?? <drive.File>[]) {
      final isDir = f.mimeType == 'application/vnd.google-apps.folder';
      items.add(
        FileEntry(
          name: f.name ?? 'unknown',
          path: f.id ?? '',
          isDirectory: isDir,
          size: f.size != null ? int.tryParse(f.size!) ?? 0 : 0,
          modified: f.modifiedTime ?? DateTime.now(),
          permissions: '',
        ),
      );
    }
    return items;
  }

  @override
  bool supports(ProviderCapability capability) {
    switch (capability) {
      case ProviderCapability.read:
      case ProviderCapability.delete:
      case ProviderCapability.list:
      case ProviderCapability.search:
        return true;
      case ProviderCapability.write:
      case ProviderCapability.move:
      case ProviderCapability.mkdir:
      case ProviderCapability.streaming:
      case ProviderCapability.symlinks:
      case ProviderCapability.permissions:
      case ProviderCapability.freeSpace:
        return false;
    }
  }

  void _checkConnection() {
    if (!isConnected) {
      throw StorageException('Not connected to Google Drive');
    }
  }
}
