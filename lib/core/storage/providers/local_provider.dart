import 'dart:async';
import 'dart:io';

import 'package:disk_usage/disk_usage.dart';
import 'package:mime/mime.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages

import '../models/connection_profile.dart';
import '../models/file_entry.dart';
import '../models/transfer_progress.dart';
import '../hidden_entry_policy.dart';
import '../storage_provider.dart';

/// A [StorageProvider] that operates on the local filesystem using `dart:io`.
///
/// This is the primary provider for desktop platforms (Windows, macOS, Linux).
/// On mobile platforms, a SAF-based provider replaces this for scoped storage
/// compliance (Sprint 2).
class LocalProvider implements StorageProvider {
  LocalProvider({this.homePathOverride});

  /// Override for the home path (useful for testing)
  final String? homePathOverride;

  @override
  ConnectionProfile? get profile => null;

  @override
  String get displayName => 'Local';

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStateChanges => const Stream.empty();

  @override
  Future<void> connect() async {
    // No-op for local filesystem
  }

  @override
  Future<void> disconnect() async {
    // No-op for local filesystem
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw StorageException(
        'Directory not found',
        code: StorageException.notFound,
        path: path,
      );
    }

    // This information is only available on macOS. Avoid spawning a failed
    // process for every directory while recursively scanning on other hosts.
    final sharedPaths = <String>{};
    if (Platform.isMacOS) {
      try {
        final res = await Process.run('sharing', ['-l']);
        if (res.exitCode == 0) {
          final output = res.stdout as String;
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('path:')) {
              final sharePath = line.split('path:')[1].trim();
              if (sharePath.isNotEmpty) {
                sharedPaths.add(sharePath);
              }
            }
          }
        }
      } catch (_) {}
    }

    final showHidden = options?.showHidden ?? false;
    final windowsHiddenPaths = await HiddenEntryPolicy.windowsHiddenPaths(path);
    final result = <FileEntry>[];

    Object? streamError;
    // Never follow links while enumerating. A junction or symlink may point
    // back to an ancestor and make recursive callers scan forever.
    final stream = dir.list(followLinks: false).handleError((e) {
      streamError = e;
      debugPrint('LocalProvider list error for path=$path: $e');
    });

    await for (final entity in stream) {
      final name = p.basename(entity.path);
      final hasPlatformHiddenAttribute = windowsHiddenPaths.contains(
        HiddenEntryPolicy.normalizeWindowsPath(entity.path),
      );
      final hidden = HiddenEntryPolicy.isHidden(
        name,
        hasPlatformHiddenAttribute: hasPlatformHiddenAttribute,
      );

      if (!showHidden && hidden) continue;

      try {
        var entry = await _entityToFileEntry(entity);
        if (entry.hidden != hidden) {
          entry = entry.copyWith(hidden: hidden);
        }
        if (sharedPaths.contains(entity.path)) {
          entry = entry.copyWith(isShared: true);
        }
        result.add(entry);
      } catch (e) {
        // Skip files that were deleted or unreadable before stat completed
      }
    }

    if (result.isEmpty && streamError != null) {
      throw StorageException(
        'Dizin okunamadı veya izin verilmedi: $streamError',
        code: StorageException.accessDenied,
        path: path,
      );
    }

    return result;
  }

  @override
  Future<FileEntry> stat(String path) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      throw StorageException(
        'Not found',
        code: StorageException.notFound,
        path: path,
      );
    }

    return _pathToFileEntry(path);
  }

  @override
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  }) async* {
    final file = File(path);
    if (!file.existsSync()) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: 'File not found: $path',
      );
      return;
    }

    final totalBytes = file.lengthSync();
    final entry = await _pathToFileEntry(path);
    var bytesTransferred = 0;

    yield TransferProgress(
      operation: TransferOperation.read,
      state: TransferState.inProgress,
      currentFile: entry,
      bytesTransferred: 0,
      totalBytes: totalBytes,
    );

    final raf = file.openSync();
    try {
      const chunkSize = 64 * 1024; // 64KB chunks
      while (bytesTransferred < totalBytes) {
        if (cancelToken?.isCancelled ?? false) {
          yield TransferProgress(
            operation: TransferOperation.read,
            state: TransferState.cancelled,
          );
          return;
        }

        final remaining = totalBytes - bytesTransferred;
        final readSize = remaining < chunkSize ? remaining : chunkSize;
        final data = raf.readSync(readSize);
        bytesTransferred += data.length;

        yield TransferProgress(
          operation: TransferOperation.read,
          state: TransferState.inProgress,
          currentFile: entry,
          bytesTransferred: bytesTransferred,
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
    } finally {
      raf.closeSync();
    }
  }

  @override
  Stream<TransferProgress> write(
    String path,
    Stream<List<int>> data, {
    CancelToken? cancelToken,
  }) async* {
    final file = File(path);
    final sink = file.openWrite();
    var bytesTransferred = 0;

    try {
      await for (final chunk in data) {
        if (cancelToken?.isCancelled ?? false) {
          await sink.close();
          // Clean up partial file
          if (file.existsSync()) {
            file.deleteSync();
          }
          yield TransferProgress(
            operation: TransferOperation.write,
            state: TransferState.cancelled,
          );
          return;
        }

        sink.add(chunk);
        bytesTransferred += chunk.length;

        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.inProgress,
          bytesTransferred: bytesTransferred,
        );
      }

      await sink.flush();
      await sink.close();

      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.completed,
        bytesTransferred: bytesTransferred,
      );
    } catch (e) {
      await sink.close();
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
      yield* _copyFile(
        sourcePath,
        destProvider,
        destPath,
        cancelToken,
        sourceEntry,
      );
    }
  }

  Stream<TransferProgress> _copyFile(
    String sourcePath,
    StorageProvider destProvider,
    String destPath,
    CancelToken? cancelToken,
    FileEntry sourceEntry,
  ) async* {
    // If same provider, use native copy
    if (destProvider is LocalProvider) {
      if (p.normalize(sourcePath) == p.normalize(destPath)) {
        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.failed,
          currentFile: sourceEntry,
          error: 'Source and destination are the same file',
        );
        return;
      }

      final sourceFile = File(sourcePath);
      final destFile = File(destPath);

      // Ensure dest directory exists
      final destDir = Directory(p.dirname(destPath));
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      final totalBytes = sourceFile.lengthSync();
      var bytesTransferred = 0;
      var lastYieldedBytes = 0;

      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.inProgress,
        currentFile: sourceEntry,
        bytesTransferred: 0,
        totalBytes: totalBytes,
      );

      // Use stream-based copy for progress
      final sourceRaf = await sourceFile.open();
      final destRaf = await destFile.open(mode: FileMode.write);
      try {
        const chunkSize = 64 * 1024;
        while (bytesTransferred < totalBytes) {
          if (cancelToken?.isCancelled ?? false) {
            await destRaf.close();
            await sourceRaf.close();
            if (await destFile.exists()) await destFile.delete();
            yield TransferProgress(
              operation: TransferOperation.copy,
              currentFile: sourceEntry,
              state: TransferState.cancelled,
            );
            return;
          }

          final remaining = totalBytes - bytesTransferred;
          final readSize = remaining < chunkSize ? remaining : chunkSize;
          final data = await sourceRaf.read(readSize);
          await destRaf.writeFrom(data);
          bytesTransferred += data.length;

          // Throttle progress updates to avoid flooding UI (update every ~1%)
          if (bytesTransferred == totalBytes ||
              (bytesTransferred - lastYieldedBytes) >
                  (totalBytes / 100).clamp(1024 * 1024, 50 * 1024 * 1024)) {
            lastYieldedBytes = bytesTransferred;
            yield TransferProgress(
              operation: TransferOperation.copy,
              state: TransferState.inProgress,
              currentFile: sourceEntry,
              bytesTransferred: bytesTransferred,
              totalBytes: totalBytes,
            );
            // Add a tiny delay to ensure UI thread gets time to render
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }

        await destRaf.close();
        await sourceRaf.close();

        yield TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.completed,
          currentFile: sourceEntry,
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
        );
      } catch (e) {
        await destRaf.close();
        await sourceRaf.close();
        yield TransferProgress(
          operation: TransferOperation.copy,
          currentFile: sourceEntry,
          state: TransferState.failed,
          error: e.toString(),
        );
      }
    } else {
      // Cross-provider: read from this, write to dest
      final totalBytes = File(sourcePath).lengthSync();
      var bytesTransferred = 0;

      // Pipe read stream to write
      final controller = StreamController<List<int>>();

      // Start reading in background
      final readStream = File(sourcePath).openRead();
      readStream.listen(
        (chunk) {
          bytesTransferred += chunk.length;
          controller.add(chunk);
        },
        onDone: () => controller.close(),
        onError: (Object e) => controller.addError(e),
      );

      // Write to dest provider
      await for (final progress in destProvider.write(
        destPath,
        controller.stream,
        cancelToken: cancelToken,
      )) {
        if (progress.state == TransferState.inProgress) {
          yield progress.copyWith(
            operation: TransferOperation.copy,
            currentFile: sourceEntry,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
          );
        } else if (progress.state == TransferState.completed) {
          yield progress.copyWith(
            operation: TransferOperation.copy,
            currentFile: sourceEntry,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
          );
        } else {
          yield progress.copyWith(
            operation: TransferOperation.copy,
            currentFile: sourceEntry,
          );
        }
      }
    }
  }

  Stream<TransferProgress> _copyDirectory(
    String sourcePath,
    StorageProvider destProvider,
    String destPath,
    CopyOptions options,
    CancelToken? cancelToken,
  ) async* {
    // Copy is independent from panel visibility: dotfiles such as .git and
    // Windows Hidden entries must always travel with their parent directory.
    final entries = await list(sourcePath, const ListOptions(showHidden: true));
    var filesTransferred = 0;
    final totalFiles = entries.length;

    // Create dest directory
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

      final sourceEntryPath = joinPath(sourcePath, entry.name);
      final destEntryPath = joinPath(destPath, entry.name);

      if (entry.isDirectory) {
        // Do not recurse into junctions/symlinked directories. On Windows a
        // junction can point back to an ancestor and otherwise never finish.
        if (entry.symlink) {
          filesTransferred++;
          yield TransferProgress(
            operation: TransferOperation.copy,
            state: TransferState.inProgress,
            filesTransferred: filesTransferred,
            totalFiles: totalFiles,
          );
          continue;
        }
        yield* _copyDirectory(
          sourceEntryPath,
          destProvider,
          destEntryPath,
          options,
          cancelToken,
        );
      } else {
        yield* _copyFile(
          sourceEntryPath,
          destProvider,
          destEntryPath,
          cancelToken,
          entry,
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
    final source = FileSystemEntity.typeSync(sourcePath);
    if (source == FileSystemEntityType.notFound) {
      throw StorageException(
        'Source not found',
        code: StorageException.notFound,
        path: sourcePath,
      );
    }

    // Ensure dest directory exists
    final destDir = Directory(p.dirname(destPath));
    if (!(await destDir.exists())) {
      await destDir.create(recursive: true);
    }

    try {
      if (source == FileSystemEntityType.directory) {
        await Directory(sourcePath).rename(destPath);
      } else {
        await File(sourcePath).rename(destPath);
      }
    } catch (e) {
      throw StorageException(
        'Move failed: $e',
        code: StorageException.accessDenied,
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
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      throw StorageException(
        'Not found',
        code: StorageException.notFound,
        path: path,
      );
    }

    try {
      if (type == FileSystemEntityType.directory) {
        Directory(path).deleteSync(recursive: true);
      } else {
        File(path).deleteSync();
      }
    } catch (e) {
      debugPrint('Standard deleteSync failed for $path: $e');
      debugPrint('Attempting fallback with rm -rf...');

      // GÜVENLİK: Koştan önce path'in makul olduğunu doğrula.
      // Kök dizin, ev dizini veya /Volumes gibi kritik dizinler silinemez.
      final normalizedPath = p.normalize(path);
      if (normalizedPath == '/' ||
          normalizedPath == p.normalize(Platform.environment['HOME'] ?? '/') ||
          normalizedPath == '/Volumes') {
        throw StorageException(
          'Güvenlik: Bu dizin silinemez: $path',
          code: StorageException.accessDenied,
          path: path,
        );
      }

      try {
        final result = await Process.run('rm', ['-rf', path]);
        if (result.exitCode != 0) {
          throw Exception(
            'rm -rf başarısız oldu (Exit code: ${result.exitCode}): ${result.stderr}',
          );
        }
      } catch (fallbackError) {
        throw StorageException(
          'Silme Başarısız: $e\nFallback Hatası: $fallbackError',
          code: StorageException.accessDenied,
          path: path,
          cause: fallbackError,
        );
      }
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) {
      throw StorageException(
        'Already exists',
        code: StorageException.alreadyExists,
        path: path,
      );
    }

    try {
      dir.createSync(recursive: true);
    } catch (e) {
      throw StorageException(
        'Mkdir failed: $e',
        code: StorageException.accessDenied,
        path: path,
        cause: e,
      );
    }
  }

  @override
  Future<bool> exists(String path) async {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  @override
  Future<String> get homePath async {
    if (homePathOverride != null) return homePathOverride!;

    try {
      if (Platform.isAndroid) {
        const primaryStorage = '/storage/emulated/0';
        if (Directory(primaryStorage).existsSync()) {
          return primaryStorage;
        }
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null && externalDir.existsSync()) {
          return externalDir.path;
        }
      }
      if (Platform.isMacOS) {
        final envHome = Platform.environment['HOME'];
        if (envHome != null && envHome.isNotEmpty) return envHome;
      }
      final home = await getApplicationDocumentsDirectory();
      return home.path;
    } catch (_) {
      // Fallback to environment variable
      final env = Platform.environment;
      if (Platform.isWindows) {
        return env['USERPROFILE'] ?? env['HOMEPATH'] ?? 'C:\\';
      }
      return env['HOME'] ?? '/';
    }
  }

  @override
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path) async {
    try {
      final totalBytes = await DiskUsage.totalSpace(path);
      final freeBytes = await DiskUsage.freeSpace(path);
      if (totalBytes != null && freeBytes != null && totalBytes > 0) {
        return DiskSpaceInfo(
          totalBytes: totalBytes,
          freeBytes: freeBytes,
          usedBytes: (totalBytes - freeBytes).clamp(0, totalBytes),
        );
      }
    } catch (_) {
      // Unit tests and older builds can lack a registered platform plugin.
      // The desktop fallback below still queries the actual target volume.
    }

    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'& { param([string]$targetPath) $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($targetPath)); $drive = [IO.DriveInfo]::new($root); Write-Output "$($drive.TotalSize) $($drive.AvailableFreeSpace)" }',
          path,
        ]);
        if (result.exitCode == 0) {
          final values = result.stdout.toString().trim().split(RegExp(r'\s+'));
          if (values.length >= 2) {
            final totalBytes = int.tryParse(values[values.length - 2]);
            final freeBytes = int.tryParse(values.last);
            if (totalBytes != null && freeBytes != null && totalBytes > 0) {
              return DiskSpaceInfo(
                totalBytes: totalBytes,
                freeBytes: freeBytes,
                usedBytes: (totalBytes - freeBytes).clamp(0, totalBytes),
              );
            }
          }
        }
      } else if (Platform.isMacOS || Platform.isLinux || Platform.isAndroid) {
        final executable = Platform.isAndroid ? '/system/bin/df' : 'df';
        final result = await Process.run(executable, ['-Pk', path]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split(RegExp(r'\r?\n'));
          final parts = lines.last.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final totalKb = int.tryParse(parts[1]);
            final usedKb = int.tryParse(parts[2]);
            final freeKb = int.tryParse(parts[3]);
            if (totalKb != null &&
                usedKb != null &&
                freeKb != null &&
                totalKb > 0) {
              return DiskSpaceInfo(
                totalBytes: totalKb * 1024,
                freeBytes: freeKb * 1024,
                usedBytes: usedKb * 1024,
              );
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  String normalizePath(String path) => p.normalize(path);

  @override
  String joinPath(String parent, String child) => p.join(parent, child);

  @override
  String basename(String path) => p.basename(path);

  @override
  String dirname(String path) => p.dirname(path);

  @override
  bool supports(ProviderCapability capability) {
    switch (capability) {
      case ProviderCapability.read:
      case ProviderCapability.write:
      case ProviderCapability.delete:
      case ProviderCapability.move:
      case ProviderCapability.mkdir:
      case ProviderCapability.list:
      case ProviderCapability.freeSpace:
      case ProviderCapability.symlinks:
      case ProviderCapability.streaming:
      case ProviderCapability.search:
        return true;
      case ProviderCapability.permissions:
        return !Platform.isWindows;
    }
  }

  Future<FileEntry> _entityToFileEntry(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isSymlink = entity is Link;
    final stat = entity.statSync();
    final isDir =
        entity is Directory ||
        (isSymlink && stat.type == FileSystemEntityType.directory);

    String? symlinkTarget;
    if (isSymlink) {
      try {
        symlinkTarget = entity.resolveSymbolicLinksSync();
      } catch (_) {
        // Broken symlink
      }
    }

    return FileEntry(
      name: name,
      path: entity.path,
      isDirectory: isDir,
      size: isDir ? 0 : stat.size,
      modified: stat.modified,
      permissions: _permissionsToString(stat.mode),
      mimeType: isDir ? null : lookupMimeType(entity.path),
      hidden: HiddenEntryPolicy.isDotHidden(name),
      symlink: isSymlink,
      symlinkTarget: symlinkTarget,
    );
  }

  Future<FileEntry> _pathToFileEntry(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final stat = FileStat.statSync(path);
    final name = p.basename(path);
    final isSymlink = type == FileSystemEntityType.link;
    final isDir =
        type == FileSystemEntityType.directory ||
        (isSymlink && stat.type == FileSystemEntityType.directory);

    return FileEntry(
      name: name,
      path: path,
      isDirectory: isDir,
      size: isDir ? 0 : stat.size,
      modified: stat.modified,
      permissions: _permissionsToString(stat.mode),
      mimeType: isDir ? null : lookupMimeType(path),
      hidden: HiddenEntryPolicy.isDotHidden(name),
      symlink: isSymlink,
    );
  }

  @override
  Future<List<FileEntry>> search(
    String path,
    String query, {
    bool recursive = false,
  }) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw StorageException(
        'Directory not found',
        code: StorageException.notFound,
        path: path,
      );
    }

    // Replace Turkish characters to make it truly case-insensitive for Turkish users
    String trToLower(String s) {
      return s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    }

    final queryLower = trToLower(query);
    final results = <FileEntry>[];

    try {
      final stream = dir
          .list(recursive: recursive, followLinks: false)
          .handleError((e) {
            // Ignore file system exceptions like permission denied during recursive search
          });

      await for (final entity in stream) {
        final name = p.basename(entity.path);
        if (trToLower(name).contains(queryLower)) {
          try {
            final entry = await _entityToFileEntry(entity);
            results.add(entry);
          } catch (_) {
            // Ignore if file was deleted or we lack stat permissions
          }
        }
      }
    } catch (e) {
      throw StorageException(
        'Arama hatası: $e',
        code: StorageException
            .accessDenied, // Yerel dosya işlemi — networkError değil
        path: path,
        cause: e,
      );
    }
    return results;
  }

  String _permissionsToString(int mode) {
    // Convert Unix mode bits to rwx string
    // Using decimal values (octal 0o400 = 256, etc.)
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
