import 'dart:async';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/models/file_entry.dart';
import '../../core/storage/models/transfer_progress.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/storage/providers/local_provider.dart';
import '../../core/storage/storage_provider_service.dart';
import 'sync_models.dart';
import 'file_operations_state.dart';

part 'file_operations_service.g.dart';

class _EntryTransferPlan {
  const _EntryTransferPlan({required this.files, required this.totalBytes});

  final List<FileEntry> files;
  final int totalBytes;

  int get totalFiles => files.length;
}

class _TransferPlan {
  const _TransferPlan(this.roots);

  final Map<String, _EntryTransferPlan> roots;

  int get totalBytes =>
      roots.values.fold(0, (sum, root) => sum + root.totalBytes);

  int get totalFiles =>
      roots.values.fold(0, (sum, root) => sum + root.totalFiles);
}

class _DeletePlan {
  const _DeletePlan({required this.files, required this.directories});

  final List<FileEntry> files;
  final List<FileEntry> directories;

  int get totalBytes => files.fold(0, (sum, entry) => sum + entry.size);

  int get totalItems => files.length + directories.length;
}

/// Service that executes file operations (copy, move, delete, rename, mkdir)
/// and updates the [OperationProgress] state.
///
/// All operations are async and report progress via [OperationProgress] provider.
/// Operations can be cancelled via [CancelToken].
@Riverpod(keepAlive: true)
class FileOperationsService extends _$FileOperationsService {
  final Set<CancelToken> _activeTokens = {};

  @override
  void build() {
    // No state needed — this is a service provider
  }
  Future<_EntryTransferPlan> _measureEntry(
    StorageProvider provider,
    FileEntry entry,
  ) async {
    if (!entry.isDirectory) {
      return _EntryTransferPlan(files: [entry], totalBytes: entry.size);
    }
    if (entry.symlink) {
      return const _EntryTransferPlan(files: [], totalBytes: 0);
    }

    final files = <FileEntry>[];
    var totalBytes = 0;
    final children = await provider.list(
      entry.path,
      const ListOptions(showHidden: true),
    );
    for (final child in children) {
      final childPlan = await _measureEntry(provider, child);
      files.addAll(childPlan.files);
      totalBytes += childPlan.totalBytes;
    }
    return _EntryTransferPlan(files: files, totalBytes: totalBytes);
  }

  Future<_TransferPlan> _buildTransferPlan(
    StorageProvider provider,
    List<FileEntry> entries,
  ) async {
    final roots = <String, _EntryTransferPlan>{};
    for (final entry in entries) {
      roots[entry.path] = await _measureEntry(provider, entry);
    }
    return _TransferPlan(roots);
  }

  Future<_DeletePlan> _buildDeletePlan(
    StorageProvider provider,
    List<FileEntry> entries,
  ) async {
    final files = <FileEntry>[];
    final directories = <FileEntry>[];

    Future<void> visit(FileEntry entry) async {
      if (!entry.isDirectory) {
        files.add(entry);
        return;
      }
      if (!entry.symlink) {
        final children = await provider.list(
          entry.path,
          const ListOptions(showHidden: true),
        );
        for (final child in children) {
          await visit(child);
        }
      }
      directories.add(entry);
    }

    for (final entry in entries) {
      await visit(entry);
    }
    return _DeletePlan(files: files, directories: directories);
  }

  /// Copy selected entries from source panel to dest path.
  ///
  /// [overwriteCallback] is called when a destination file already exists.
  /// It receives the file name and should return:
  ///   'overwrite' — overwrite the existing file
  ///   'rename'    — auto-rename (add "copy N" suffix)
  ///   'skip'      — skip this file
  ///   null        — cancel entire operation
  Future<TransferProgress> copy({
    required StorageProvider sourceProvider,
    required List<FileEntry> entries,
    required StorageProvider destProvider,
    required String destPath,
    bool isMove = false,
    bool publishCompletion = true,
    Future<String?> Function(String fileName)? overwriteCallback,
  }) async {
    final operation = isMove ? TransferOperation.move : TransferOperation.copy;
    final progress = ref.read(operationProgressProvider.notifier);
    if (entries.isEmpty) {
      final result = TransferProgress(
        operation: operation,
        state: TransferState.completed,
      );
      if (publishCompletion) progress.setProgress(result);
      return result;
    }
    if (_activeTokens.isNotEmpty) {
      final result = TransferProgress(
        operation: operation,
        state: TransferState.failed,
        error: 'Another file operation is already running.',
      );
      progress.setProgress(result);
      return result;
    }

    final cancelToken = CancelToken();
    _activeTokens.add(cancelToken);
    progress.setProgress(
      TransferProgress(
        operation: operation,
        state: TransferState.inProgress,
        currentFile: FileEntry(
          name: isMove ? 'Preparing move...' : 'Preparing copy...',
          path: '',
          isDirectory: true,
          size: 0,
        ),
        totalFiles: entries.length,
      ),
    );

    late final _TransferPlan transferPlan;
    try {
      transferPlan = await _buildTransferPlan(sourceProvider, entries);
    } catch (error) {
      final result = TransferProgress(
        operation: operation,
        state: TransferState.failed,
        error: error.toString(),
      );
      progress.setProgress(result);
      _activeTokens.remove(cancelToken);
      return result;
    }

    var overallTotalBytes = transferPlan.totalBytes;
    var totalFiles = transferPlan.totalFiles;
    var overallBytesTransferred = 0;
    var operationFailed = false;
    String? operationError;
    final transferredByPath = <String, int>{};
    final completedPaths = <String>{};
    final rateTracker = TransferRateTracker();
    rateTracker.addSample(0);
    FileEntry? lastCurrentFile;
    var lastCurrentBytes = 0;
    var lastCurrentTotal = 0;
    var latestSpeed = 0.0;

    progress.setProgress(
      TransferProgress(
        operation: operation,
        state: TransferState.inProgress,
        overallTotalBytes: overallTotalBytes,
        totalFiles: totalFiles,
      ),
    );

    for (var i = 0; i < entries.length; i++) {
      if (cancelToken.isCancelled) break;

      final entry = entries[i];
      final rootPlan =
          transferPlan.roots[entry.path] ??
          const _EntryTransferPlan(files: [], totalBytes: 0);
      final dirName = destProvider.normalizePath(destPath);
      var destEntryPath = destProvider.joinPath(dirName, entry.name);

      if (await destProvider.exists(destEntryPath)) {
        final decision = overwriteCallback != null
            ? await overwriteCallback(entry.name)
            : 'rename';

        if (decision == null) {
          cancelToken.cancel();
          break;
        } else if (decision == 'skip') {
          overallTotalBytes -= rootPlan.totalBytes;
          totalFiles -= rootPlan.totalFiles;
          if (isMove) {
            operationFailed = true;
            operationError = 'One or more entries were skipped.';
          }
          continue;
        } else if (decision == 'rename') {
          var counter = 1;
          final originalName = destProvider.basename(destEntryPath);
          while (await destProvider.exists(destEntryPath)) {
            if (!entry.isDirectory && originalName.contains('.')) {
              final dotIndex = originalName.lastIndexOf('.');
              final base = originalName.substring(0, dotIndex);
              final ext = originalName.substring(dotIndex);
              destEntryPath = destProvider.joinPath(
                dirName,
                '$base copy $counter$ext',
              );
            } else {
              destEntryPath = destProvider.joinPath(
                dirName,
                '$originalName copy $counter',
              );
            }
            counter++;
          }
        }
      }

      FileEntry? activeFile = entry.isDirectory
          ? (rootPlan.files.isEmpty ? null : rootPlan.files.first)
          : entry;
      var fallbackFileIndex = entry.isDirectory && activeFile != null ? 1 : 0;
      var activeFileCompleted = false;
      var previousProviderBytes = 0;

      progress.setProgress(
        TransferProgress(
          operation: operation,
          state: TransferState.inProgress,
          currentFile: activeFile ?? entry,
          totalBytes: activeFile?.size ?? 0,
          overallBytesTransferred: overallBytesTransferred,
          overallTotalBytes: overallTotalBytes,
          filesTransferred: completedPaths.length,
          totalFiles: totalFiles,
          speed: latestSpeed,
        ),
      );

      try {
        final stream = sourceProvider.copy(
          entry.path,
          destProvider,
          destEntryPath,
          cancelToken: cancelToken,
        );

        await for (final providerProgress in stream) {
          var currentFile = providerProgress.currentFile;
          if (currentFile == null && !entry.isDirectory) {
            currentFile = entry;
          } else if (currentFile == null && providerProgress.totalBytes > 0) {
            final startsNextFile =
                activeFile == null ||
                activeFileCompleted ||
                providerProgress.bytesTransferred < previousProviderBytes;
            if (startsNextFile && fallbackFileIndex < rootPlan.files.length) {
              currentFile = rootPlan.files[fallbackFileIndex];
              fallbackFileIndex++;
            } else {
              currentFile = activeFile;
            }
          }

          if (currentFile != null && !currentFile.isDirectory) {
            activeFile = currentFile;
            final currentTotal = providerProgress.totalBytes > 0
                ? providerProgress.totalBytes
                : currentFile.size;
            var currentBytes = providerProgress.bytesTransferred;
            if (currentTotal > 0 && currentBytes > currentTotal) {
              currentBytes = currentTotal;
            }
            if (currentBytes < 0) currentBytes = 0;

            final previous = transferredByPath[currentFile.path] ?? 0;
            if (currentBytes > previous) {
              overallBytesTransferred += currentBytes - previous;
              transferredByPath[currentFile.path] = currentBytes;
            }

            if (providerProgress.state == TransferState.completed) {
              final completedBytes = currentTotal > 0
                  ? currentTotal
                  : currentBytes;
              final tracked = transferredByPath[currentFile.path] ?? 0;
              if (completedBytes > tracked) {
                overallBytesTransferred += completedBytes - tracked;
                transferredByPath[currentFile.path] = completedBytes;
              }
              completedPaths.add(currentFile.path);
              activeFileCompleted = true;
            } else if (providerProgress.totalBytes > 0) {
              activeFileCompleted = false;
            }

            lastCurrentFile = currentFile;
            lastCurrentBytes = currentBytes;
            lastCurrentTotal = currentTotal;
            previousProviderBytes = providerProgress.bytesTransferred;
          }

          if (overallBytesTransferred > overallTotalBytes &&
              overallTotalBytes > 0) {
            overallBytesTransferred = overallTotalBytes;
          }
          latestSpeed = rateTracker.addSample(
            overallBytesTransferred,
            timestamp: providerProgress.timestamp,
          );

          progress.setProgress(
            providerProgress.copyWith(
              operation: operation,
              state: providerProgress.state == TransferState.completed
                  ? TransferState.inProgress
                  : providerProgress.state,
              currentFile: currentFile ?? activeFile ?? entry,
              bytesTransferred: lastCurrentBytes,
              totalBytes: lastCurrentTotal,
              overallBytesTransferred: overallBytesTransferred,
              overallTotalBytes: overallTotalBytes,
              filesTransferred: completedPaths.length,
              totalFiles: totalFiles,
              speed: latestSpeed,
            ),
          );
          if (providerProgress.state == TransferState.failed) {
            operationFailed = true;
            operationError ??= providerProgress.error;
          }
        }
      } catch (error) {
        operationFailed = true;
        operationError ??= error.toString();
        try {
          if (await destProvider.exists(destEntryPath)) {
            await destProvider.delete(destEntryPath);
          }
        } catch (_) {}

        progress.setProgress(
          TransferProgress(
            operation: operation,
            state: TransferState.failed,
            error: error.toString(),
            currentFile: activeFile ?? entry,
            bytesTransferred: lastCurrentBytes,
            totalBytes: lastCurrentTotal,
            overallBytesTransferred: overallBytesTransferred,
            overallTotalBytes: overallTotalBytes,
            filesTransferred: completedPaths.length,
            totalFiles: totalFiles,
            speed: latestSpeed,
          ),
        );
      }
    }

    final finalState = cancelToken.isCancelled
        ? TransferState.cancelled
        : operationFailed
        ? TransferState.failed
        : TransferState.completed;
    if (finalState == TransferState.completed) {
      overallBytesTransferred = overallTotalBytes;
    }
    final result = TransferProgress(
      operation: operation,
      state: finalState,
      currentFile: lastCurrentFile,
      bytesTransferred: lastCurrentBytes,
      totalBytes: lastCurrentTotal,
      overallBytesTransferred: overallBytesTransferred,
      overallTotalBytes: overallTotalBytes,
      filesTransferred: completedPaths.length,
      totalFiles: totalFiles,
      speed: latestSpeed,
      error: operationError,
    );
    progress.setProgress(
      finalState == TransferState.completed && !publishCompletion
          ? result.copyWith(state: TransferState.inProgress)
          : result,
    );

    _activeTokens.remove(cancelToken);
    return result;
  }

  /// Move entries.
  Future<void> move({
    required StorageProvider sourceProvider,
    required List<FileEntry> entries,
    required StorageProvider destProvider,
    required String destPath,
  }) async {
    if (entries.isEmpty) return;

    if (sourceProvider == destProvider) {
      final progress = ref.read(operationProgressProvider.notifier);
      late final _TransferPlan transferPlan;
      try {
        transferPlan = await _buildTransferPlan(sourceProvider, entries);
      } catch (_) {
        transferPlan = _TransferPlan({
          for (final entry in entries)
            entry.path: _EntryTransferPlan(
              files: entry.isDirectory ? const [] : [entry],
              totalBytes: entry.size,
            ),
        });
      }

      final overallTotalBytes = transferPlan.totalBytes;
      final totalFiles = transferPlan.totalFiles > 0
          ? transferPlan.totalFiles
          : entries.length;
      final rateTracker = TransferRateTracker();
      rateTracker.addSample(0);
      var overallBytesTransferred = 0;
      var filesTransferred = 0;
      var speed = 0.0;
      var fallbackStart = entries.length;

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final entryPlan =
            transferPlan.roots[entry.path] ??
            _EntryTransferPlan(
              files: entry.isDirectory ? const [] : [entry],
              totalBytes: entry.size,
            );
        final destEntryPath = sourceProvider.joinPath(destPath, entry.name);

        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.move,
            state: TransferState.inProgress,
            currentFile: entry,
            totalBytes: entryPlan.totalBytes,
            overallBytesTransferred: overallBytesTransferred,
            overallTotalBytes: overallTotalBytes,
            filesTransferred: filesTransferred,
            totalFiles: totalFiles,
            speed: speed,
          ),
        );

        try {
          await sourceProvider.move(entry.path, destEntryPath);
          overallBytesTransferred += entryPlan.totalBytes;
          filesTransferred += entryPlan.totalFiles > 0
              ? entryPlan.totalFiles
              : 1;
          speed = rateTracker.addSample(overallBytesTransferred);
          progress.setProgress(
            TransferProgress(
              operation: TransferOperation.move,
              state: TransferState.inProgress,
              currentFile: entry,
              bytesTransferred: entryPlan.totalBytes,
              totalBytes: entryPlan.totalBytes,
              overallBytesTransferred: overallBytesTransferred,
              overallTotalBytes: overallTotalBytes,
              filesTransferred: filesTransferred,
              totalFiles: totalFiles,
              speed: speed,
            ),
          );
        } catch (_) {
          fallbackStart = i;
          break;
        }
      }

      if (fallbackStart == entries.length) {
        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.move,
            state: TransferState.completed,
            overallBytesTransferred: overallTotalBytes,
            overallTotalBytes: overallTotalBytes,
            filesTransferred: totalFiles,
            totalFiles: totalFiles,
            speed: speed,
          ),
        );
        return;
      }

      entries = entries.sublist(fallbackStart);
    }

    final copyResult = await copy(
      sourceProvider: sourceProvider,
      entries: entries,
      destProvider: destProvider,
      destPath: destPath,
      isMove: true,
      publishCompletion: false,
    );

    if (copyResult.state == TransferState.completed) {
      final progress = ref.read(operationProgressProvider.notifier);
      try {
        await delete(
          provider: sourceProvider,
          entries: entries,
          hideProgress: true,
        );
        progress.setProgress(copyResult);
      } catch (error) {
        progress.setProgress(
          copyResult.copyWith(
            state: TransferState.failed,
            error: error.toString(),
          ),
        );
        rethrow;
      }
    }
  }

  /// Delete entries with per-item and complete-batch progress.
  Future<void> delete({
    required StorageProvider provider,
    required List<FileEntry> entries,
    bool hideProgress = false,
    bool wipe = false,
  }) async {
    if (entries.isEmpty) return;

    if (hideProgress) {
      for (final entry in entries) {
        if (wipe) await _wipeFile(provider, entry.path);
        await provider.delete(entry.path);
      }
      return;
    }

    final progress = ref.read(operationProgressProvider.notifier);
    late final _DeletePlan deletePlan;
    try {
      deletePlan = await _buildDeletePlan(provider, entries);
    } catch (error) {
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.delete,
          state: TransferState.failed,
          error: error.toString(),
        ),
      );
      rethrow;
    }

    final targets = [...deletePlan.files, ...deletePlan.directories];
    final totalBytes = deletePlan.totalBytes;
    final totalItems = deletePlan.totalItems;
    final rateTracker = TransferRateTracker();
    rateTracker.addSample(0);
    var overallBytesDeleted = 0;
    var itemsDeleted = 0;
    var speed = 0.0;

    for (final entry in targets) {
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.delete,
          state: TransferState.inProgress,
          currentFile: entry,
          totalBytes: entry.size,
          overallBytesTransferred: overallBytesDeleted,
          overallTotalBytes: totalBytes,
          filesTransferred: itemsDeleted,
          totalFiles: totalItems,
          speed: speed,
        ),
      );

      try {
        if (wipe && !entry.isDirectory) {
          await _wipeFile(provider, entry.path);
        }
        await provider.delete(entry.path);
        overallBytesDeleted += entry.size;
        itemsDeleted++;
        speed = rateTracker.addSample(overallBytesDeleted);
        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.delete,
            state: TransferState.inProgress,
            currentFile: entry,
            bytesTransferred: entry.size,
            totalBytes: entry.size,
            overallBytesTransferred: overallBytesDeleted,
            overallTotalBytes: totalBytes,
            filesTransferred: itemsDeleted,
            totalFiles: totalItems,
            speed: speed,
          ),
        );
      } catch (error) {
        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.delete,
            state: TransferState.failed,
            error: error.toString(),
            currentFile: entry,
            overallBytesTransferred: overallBytesDeleted,
            overallTotalBytes: totalBytes,
            filesTransferred: itemsDeleted,
            totalFiles: totalItems,
            speed: speed,
          ),
        );
        throw Exception('Silme hatası: $error');
      }
    }

    progress.setProgress(
      TransferProgress(
        operation: TransferOperation.delete,
        state: TransferState.completed,
        overallBytesTransferred: totalBytes,
        overallTotalBytes: totalBytes,
        filesTransferred: totalItems,
        totalFiles: totalItems,
        speed: speed,
      ),
    );
  }

  Future<void> _wipeFile(StorageProvider provider, String path) async {
    try {
      final stat = await provider.stat(path);
      if (stat.isDirectory) {
        final children = await provider.list(
          path,
          const ListOptions(showHidden: true),
        );
        for (final child in children) {
          await _wipeFile(provider, child.path);
        }
      } else {
        final size = stat.size;
        if (size > 0) {
          final controller = StreamController<List<int>>();
          final stream = provider.write(path, controller.stream);
          final writeFuture = stream.drain();

          const chunkSize = 64 * 1024;
          var remaining = size;
          while (remaining > 0) {
            final writeSize = remaining < chunkSize ? remaining : chunkSize;
            controller.add(List<int>.filled(writeSize, 0));
            remaining -= writeSize;
            await Future.delayed(Duration.zero);
          }
          await controller.close();
          await writeFuture;
        }
      }
    } catch (e) {
      // Ignore wipe errors and fall back to normal delete
    }
  }

  /// Rename a single entry
  Future<void> rename({
    required StorageProvider provider,
    required FileEntry entry,
    required String newName,
  }) async {
    final progress = ref.read(operationProgressProvider.notifier);

    progress.setProgress(
      TransferProgress(
        operation: TransferOperation.move,
        state: TransferState.inProgress,
        currentFile: entry,
      ),
    );

    try {
      await provider.rename(entry.path, newName);
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.move,
          state: TransferState.completed,
          currentFile: entry,
        ),
      );
    } catch (e) {
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.move,
          state: TransferState.failed,
          error: e.toString(),
          currentFile: entry,
        ),
      );
      rethrow;
    }
  }

  /// Create a new directory
  Future<void> mkdir({
    required StorageProvider provider,
    required String parentPath,
    required String name,
  }) async {
    final newPath = provider.joinPath(parentPath, name);
    await provider.mkdir(newPath);
  }

  /// Create a new empty file
  Future<void> createFile({
    required StorageProvider provider,
    required String parentPath,
    required String name,
  }) async {
    final newPath = provider.joinPath(parentPath, name);
    await provider.write(newPath, const Stream.empty()).last;
  }

  /// Cancel the current operation
  void cancelOperation() {
    for (final token in _activeTokens) {
      token.cancel();
    }
    _activeTokens.clear();
  }

  /// Paste from clipboard to the given destination
  Future<void> paste({
    required StorageProvider destProvider,
    required String destPath,
  }) async {
    final clipboard = ref.read(fileClipboardProvider);
    if ((clipboard == null)) return;

    final registry = ref.read(storageProviderRegistryProvider.notifier);
    final sourceProvider = registry.get(clipboard.sourceProviderId);

    if (sourceProvider == null) return;

    final entries = <FileEntry>[];
    for (final path in clipboard.sourcePaths) {
      try {
        entries.add(await sourceProvider.stat(path));
      } catch (_) {
        // Skip missing files
      }
    }

    if (clipboard.operation == ClipboardOperation.copy) {
      await copy(
        sourceProvider: sourceProvider,
        entries: entries,
        destProvider: destProvider,
        destPath: destPath,
      );
    } else {
      // For move within same provider, use move
      if (sourceProvider == destProvider) {
        await move(
          sourceProvider: destProvider,
          entries: entries,
          destProvider: destProvider,
          destPath: destPath,
        );
      } else {
        // Cross-provider move = copy + delete
        await copy(
          sourceProvider: sourceProvider,
          entries: entries,
          destProvider: destProvider,
          destPath: destPath,
        );
        await delete(provider: sourceProvider, entries: entries);
      }
    }

    ref.read(fileClipboardProvider.notifier).clear();
  }

  Future<List<SyncItem>> analyzeSync({
    required StorageProvider sourceProvider,
    required String sourcePath,
    required StorageProvider destProvider,
    required String destPath,
    bool publishCompletion = true,
  }) async {
    final cancelToken = CancelToken();
    _activeTokens.add(cancelToken);
    final progress = ref.read(operationProgressProvider.notifier);

    progress.setProgress(
      TransferProgress(
        operation: TransferOperation.sync,
        state: TransferState.inProgress,
        currentFile: FileEntry(
          name: 'Scanning...',
          path: '',
          isDirectory: true,
          size: 0,
        ),
      ),
    );

    try {
      var scannedCount = 0;
      var scanLimitExceeded = false;
      const maxScannedEntries = 100000;
      const maxScanDepth = 128;
      final visitedDirectories = <String>{};
      final syncItems = <SyncItem>[];

      Future<void> scanDirectory(String currentPath, {int depth = 0}) async {
        if (cancelToken.isCancelled || scanLimitExceeded) return;
        if (depth > maxScanDepth) {
          scanLimitExceeded = true;
          return;
        }
        final normalizedPath = sourceProvider.normalizePath(currentPath);
        if (!visitedDirectories.add(normalizedPath)) return;

        try {
          final entries = await sourceProvider.list(
            currentPath,
            const ListOptions(showHidden: true),
          );
          for (final entry in entries) {
            if (cancelToken.isCancelled || scanLimitExceeded) return;
            if (scannedCount >= maxScannedEntries) {
              scanLimitExceeded = true;
              return;
            }

            scannedCount++;
            if (scannedCount % 50 == 0) {
              progress.setProgress(
                TransferProgress(
                  operation: TransferOperation.sync,
                  state: TransferState.inProgress,
                  currentFile: FileEntry(
                    name: 'Scanning: $scannedCount files...',
                    path: '',
                    isDirectory: true,
                    size: 0,
                  ),
                ),
              );
              await Future.delayed(const Duration(milliseconds: 1));
            }

            if (entry.isDirectory) {
              // Never recurse through symlinked directories. Providers that
              // expose links must preserve the symlink bit in FileEntry.
              if (entry.symlink) continue;
              await scanDirectory(
                sourceProvider.joinPath(currentPath, entry.name),
                depth: depth + 1,
              );
            } else {
              final relativePath = sourceProvider
                  .normalizePath(entry.path)
                  .replaceFirst(sourceProvider.normalizePath(sourcePath), '');
              final cleanRelative =
                  relativePath.startsWith('/') || relativePath.startsWith('\\')
                  ? relativePath.substring(1)
                  : relativePath;

              final destEntryPath = destProvider.joinPath(
                destPath,
                cleanRelative,
              );
              final relativeDepth = cleanRelative.split('/').length - 1;

              FileEntry? destinationEntry;
              var status = SyncStatus.missing;
              String? comparisonReason;
              String? error;
              if (await destProvider.exists(destEntryPath)) {
                try {
                  destinationEntry = await destProvider.stat(destEntryPath);
                  final sourceModified = entry.modified;
                  final destinationModified = destinationEntry.modified;
                  final datesHaveDifferentAvailability =
                      (sourceModified == null) != (destinationModified == null);
                  final timestampsDiffer =
                      datesHaveDifferentAvailability ||
                      (sourceModified != null &&
                          destinationModified != null &&
                          sourceModified.difference(destinationModified).abs() >
                              const Duration(seconds: 2));
                  final sizesDiffer = entry.size != destinationEntry.size;
                  status = sizesDiffer || timestampsDiffer
                      ? SyncStatus.modified
                      : SyncStatus.identical;
                  comparisonReason = switch ((sizesDiffer, timestampsDiffer)) {
                    (true, true) => 'sizeAndModified',
                    (true, false) => 'size',
                    (false, true) => 'modified',
                    (false, false) => null,
                  };
                } catch (exception) {
                  status = SyncStatus.inaccessible;
                  error = exception.toString().split('\n').first;
                  comparisonReason = 'destinationUnreadable';
                }
              }

              syncItems.add(
                SyncItem(
                  sourceEntry: entry,
                  destinationEntry: destinationEntry,
                  relativePath: cleanRelative,
                  depth: relativeDepth,
                  status: status,
                  isSelected:
                      status != SyncStatus.identical &&
                      status != SyncStatus.inaccessible,
                  comparisonReason: comparisonReason,
                  error: error,
                ),
              );
            }
          }
        } catch (error) {
          final normalizedCurrent = sourceProvider.normalizePath(currentPath);
          final normalizedRoot = sourceProvider.normalizePath(sourcePath);
          var relativePath = normalizedCurrent.replaceFirst(normalizedRoot, '');
          while (relativePath.startsWith('/') ||
              relativePath.startsWith('\\')) {
            relativePath = relativePath.substring(1);
          }
          syncItems.add(
            SyncItem(
              sourceEntry: FileEntry(
                name: sourceProvider.basename(currentPath),
                path: currentPath,
                isDirectory: true,
                size: 0,
              ),
              relativePath: relativePath.isEmpty ? '.' : relativePath,
              depth: relativePath.isEmpty ? 0 : relativePath.split('/').length,
              status: SyncStatus.inaccessible,
              isSelected: false,
              comparisonReason: 'sourceUnreadable',
              error: error.toString().split('\n').first,
            ),
          );
          progress.setProgress(
            TransferProgress(
              operation: TransferOperation.sync,
              state: TransferState.inProgress,
              currentFile: FileEntry(
                name:
                    'Uyarı: Klasör okunamadı — ${error.toString().split('\n').first}',
                path: currentPath,
                isDirectory: true,
                size: 0,
              ),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      await scanDirectory(sourcePath);
      if (scanLimitExceeded) {
        throw StateError(
          'Synchronization scan exceeded the safe limit of '
          '$maxScannedEntries entries or $maxScanDepth directory levels.',
        );
      }

      if (cancelToken.isCancelled) {
        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.sync,
            state: TransferState.cancelled,
          ),
        );
        _activeTokens.remove(cancelToken);
        return [];
      }

      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.sync,
          state: publishCompletion
              ? TransferState.completed
              : TransferState.inProgress,
        ),
      );

      // Sort by relative path alphabetically
      syncItems.sort((a, b) => a.relativePath.compareTo(b.relativePath));

      return syncItems;
    } catch (e) {
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.sync,
          state: TransferState.failed,
          error: e.toString(),
        ),
      );
      rethrow;
    } finally {
      _activeTokens.remove(cancelToken);
    }
  }

  Future<void> _prepareSyncDirectories({
    required StorageProvider destProvider,
    required String destPath,
    required List<SyncItem> selectedItems,
  }) async {
    final directories = <String>{destPath};
    for (final item in selectedItems) {
      final segments = item.relativePath
          .replaceAll('\\', '/')
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      for (var index = 0; index < segments.length - 1; index++) {
        directories.add(
          destProvider.joinPath(destPath, segments.take(index + 1).join('/')),
        );
      }
    }
    final ordered = directories.toList()
      ..sort((left, right) => left.length.compareTo(right.length));

    if (destProvider is LocalProvider) {
      for (final directory in ordered) {
        await Directory(directory).create(recursive: true);
      }
      return;
    }
    for (final directory in ordered) {
      if (!await destProvider.exists(directory)) {
        await destProvider.mkdir(directory);
      }
    }
  }

  Stream<TransferProgress> _copySyncItem({
    required StorageProvider sourceProvider,
    required StorageProvider destProvider,
    required SyncItem item,
    required String destEntryPath,
    required CancelToken cancelToken,
  }) async* {
    if (sourceProvider is! LocalProvider || destProvider is! LocalProvider) {
      yield* sourceProvider.copy(
        item.sourceEntry.path,
        destProvider,
        destEntryPath,
        options: const CopyOptions(overwrite: true),
        cancelToken: cancelToken,
      );
      return;
    }
    if (sourceProvider.normalizePath(item.sourceEntry.path) ==
        destProvider.normalizePath(destEntryPath)) {
      throw StateError('Source and destination are the same file.');
    }
    if (cancelToken.isCancelled) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.cancelled,
        currentFile: item.sourceEntry,
        totalBytes: item.sourceEntry.size,
      );
      return;
    }

    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.inProgress,
      currentFile: item.sourceEntry,
      totalBytes: item.sourceEntry.size,
    );
    final copied = await File(item.sourceEntry.path).copy(destEntryPath);
    final modified = item.sourceEntry.modified;
    if (modified != null) await copied.setLastModified(modified);
    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.completed,
      currentFile: item.sourceEntry,
      bytesTransferred: item.sourceEntry.size,
      totalBytes: item.sourceEntry.size,
    );
  }

  Future<SyncExecutionResult> executeSync({
    required StorageProvider sourceProvider,
    required StorageProvider destProvider,
    required String destPath,
    required List<SyncItem> selectedItems,
    bool publishCompletion = true,
  }) async {
    final cancelToken = CancelToken();
    _activeTokens.add(cancelToken);
    final progress = ref.read(operationProgressProvider.notifier);
    final overallTotalBytes = selectedItems.fold<int>(
      0,
      (sum, item) => sum + item.sourceEntry.size,
    );
    final rateTracker = TransferRateTracker();
    rateTracker.addSample(0);
    var overallBytesTransferred = 0;
    var filesTransferred = 0;
    var speed = 0.0;
    var operationFailed = false;
    var createdFiles = 0;
    var updatedFiles = 0;
    var failedFiles = 0;
    final failures = <SyncFileFailure>[];
    FileEntry? currentFile;
    var currentBytes = 0;
    var currentTotal = 0;

    progress.setProgress(
      TransferProgress(
        operation: TransferOperation.sync,
        state: TransferState.inProgress,
        overallTotalBytes: overallTotalBytes,
        totalFiles: selectedItems.length,
      ),
    );

    try {
      await _prepareSyncDirectories(
        destProvider: destProvider,
        destPath: destPath,
        selectedItems: selectedItems,
      );
      for (final item in selectedItems) {
        if (cancelToken.isCancelled) break;

        currentFile = item.sourceEntry;
        currentBytes = 0;
        currentTotal = item.sourceEntry.size;
        var lastPublishedBytes = 0;
        final completedBefore = overallBytesTransferred;
        var itemFailed = false;
        final destEntryPath = destProvider.joinPath(
          destPath,
          item.relativePath,
        );

        progress.setProgress(
          TransferProgress(
            operation: TransferOperation.sync,
            state: TransferState.inProgress,
            currentFile: currentFile,
            totalBytes: currentTotal,
            overallBytesTransferred: overallBytesTransferred,
            overallTotalBytes: overallTotalBytes,
            filesTransferred: filesTransferred,
            totalFiles: selectedItems.length,
            speed: speed,
          ),
        );

        try {
          final stream = _copySyncItem(
            sourceProvider: sourceProvider,
            destProvider: destProvider,
            item: item,
            destEntryPath: destEntryPath,
            cancelToken: cancelToken,
          );

          await for (final providerProgress in stream) {
            currentTotal = providerProgress.totalBytes > 0
                ? providerProgress.totalBytes
                : item.sourceEntry.size;
            currentBytes = providerProgress.bytesTransferred;
            if (currentTotal > 0 && currentBytes > currentTotal) {
              currentBytes = currentTotal;
            }
            overallBytesTransferred = completedBefore + currentBytes;
            if (overallBytesTransferred > overallTotalBytes &&
                overallTotalBytes > 0) {
              overallBytesTransferred = overallTotalBytes;
            }
            speed = rateTracker.addSample(
              overallBytesTransferred,
              timestamp: providerProgress.timestamp,
            );
            final progressInterval = currentTotal > 0
                ? (currentTotal ~/ 100).clamp(1024 * 1024, 50 * 1024 * 1024)
                : 1024 * 1024;
            final shouldPublish =
                providerProgress.state != TransferState.inProgress ||
                currentBytes == 0 ||
                currentBytes >= currentTotal ||
                currentBytes - lastPublishedBytes >= progressInterval;
            if (shouldPublish) {
              lastPublishedBytes = currentBytes;
              progress.setProgress(
                TransferProgress(
                  operation: TransferOperation.sync,
                  state: providerProgress.state == TransferState.cancelled
                      ? TransferState.cancelled
                      : TransferState.inProgress,
                  currentFile: currentFile,
                  filesTransferred: filesTransferred,
                  totalFiles: selectedItems.length,
                  bytesTransferred: currentBytes,
                  totalBytes: currentTotal,
                  overallBytesTransferred: overallBytesTransferred,
                  overallTotalBytes: overallTotalBytes,
                  speed: speed,
                  error: providerProgress.error,
                ),
              );
            }
            if (providerProgress.state == TransferState.failed && !itemFailed) {
              operationFailed = true;
              itemFailed = true;
              failedFiles++;
              failures.add(
                SyncFileFailure(
                  relativePath: item.relativePath,
                  message: providerProgress.error ?? 'Transfer failed',
                ),
              );
            }
          }

          if (!itemFailed) {
            currentBytes = item.sourceEntry.size;
            overallBytesTransferred = completedBefore + item.sourceEntry.size;
            filesTransferred++;
            speed = rateTracker.addSample(overallBytesTransferred);
            if (item.status == SyncStatus.missing) {
              createdFiles++;
            } else {
              updatedFiles++;
            }
          }
        } catch (error) {
          operationFailed = true;
          if (!itemFailed) {
            failedFiles++;
            failures.add(
              SyncFileFailure(
                relativePath: item.relativePath,
                message: error.toString().split('\n').first,
              ),
            );
          }
          progress.setProgress(
            TransferProgress(
              operation: TransferOperation.sync,
              state: TransferState.inProgress,
              currentFile: FileEntry(
                name:
                    'Hata: ${item.relativePath} — ${error.toString().split('\n').first}',
                path: item.relativePath,
                isDirectory: false,
              ),
              bytesTransferred: currentBytes,
              totalBytes: currentTotal,
              overallBytesTransferred: overallBytesTransferred,
              overallTotalBytes: overallTotalBytes,
              filesTransferred: filesTransferred,
              totalFiles: selectedItems.length,
              speed: speed,
              error: error.toString(),
            ),
          );
        }
      }

      final state = cancelToken.isCancelled
          ? TransferState.cancelled
          : operationFailed
          ? TransferState.failed
          : TransferState.completed;
      if (state == TransferState.completed) {
        overallBytesTransferred = overallTotalBytes;
        filesTransferred = selectedItems.length;
      }
      final finalProgress = TransferProgress(
        operation: TransferOperation.sync,
        state: state,
        currentFile: currentFile,
        bytesTransferred: currentBytes,
        totalBytes: currentTotal,
        overallBytesTransferred: overallBytesTransferred,
        overallTotalBytes: overallTotalBytes,
        filesTransferred: filesTransferred,
        totalFiles: selectedItems.length,
        speed: speed,
      );
      progress.setProgress(
        state == TransferState.completed && !publishCompletion
            ? finalProgress.copyWith(state: TransferState.inProgress)
            : finalProgress,
      );
    } catch (error) {
      failedFiles++;
      failures.add(
        SyncFileFailure(
          relativePath: currentFile?.path ?? '<operation>',
          message: error.toString().split('\n').first,
        ),
      );
      progress.setProgress(
        TransferProgress(
          operation: TransferOperation.sync,
          state: TransferState.failed,
          error: error.toString(),
          currentFile: currentFile,
          bytesTransferred: currentBytes,
          totalBytes: currentTotal,
          overallBytesTransferred: overallBytesTransferred,
          overallTotalBytes: overallTotalBytes,
          filesTransferred: filesTransferred,
          totalFiles: selectedItems.length,
          speed: speed,
        ),
      );
    } finally {
      _activeTokens.remove(cancelToken);
    }
    return SyncExecutionResult(
      createdFiles: createdFiles,
      updatedFiles: updatedFiles,
      failedFiles: failedFiles,
      cancelled: cancelToken.isCancelled,
      transferredBytes: overallBytesTransferred,
      failures: List.unmodifiable(failures),
    );
  }
}
