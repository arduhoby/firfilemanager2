import 'dart:io';

import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/core/storage/providers/local_provider.dart';
import 'package:fir_file_manager/core/storage/storage_provider.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_service.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/storage/mock_storage_provider.dart';

class _TrackingLocalProvider extends LocalProvider {
  int copyCalls = 0;

  @override
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options = const CopyOptions(),
    CancelToken? cancelToken,
  }) {
    copyCalls++;
    return super.copy(
      sourcePath,
      destProvider,
      destPath,
      options: options,
      cancelToken: cancelToken,
    );
  }
}

class _BurstProgressProvider extends MockStorageProvider {
  @override
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options = const CopyOptions(),
    CancelToken? cancelToken,
  }) async* {
    const chunkSize = 64 * 1024;
    const chunkCount = 256;
    const totalBytes = chunkSize * chunkCount;
    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.inProgress,
      bytesTransferred: 0,
      totalBytes: totalBytes,
    );
    for (var index = 1; index <= chunkCount; index++) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.inProgress,
        bytesTransferred: chunkSize * index,
        totalBytes: totalBytes,
      );
    }
    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.completed,
      bytesTransferred: totalBytes,
      totalBytes: totalBytes,
    );
  }
}

class _CountingMockStorageProvider extends MockStorageProvider {
  final Map<String, int> existsCalls = {};
  final List<String> mkdirCalls = [];

  @override
  Future<bool> exists(String path) {
    existsCalls[path] = (existsCalls[path] ?? 0) + 1;
    return super.exists(path);
  }

  @override
  Future<void> mkdir(String path) {
    mkdirCalls.add(path);
    return super.mkdir(path);
  }
}

void main() {
  group('TransferProgress', () {
    test('reports independent current-file and overall progress', () {
      final progress = TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.inProgress,
        bytesTransferred: 300,
        totalBytes: 1000,
        overallBytesTransferred: 2300,
        overallTotalBytes: 5000,
        filesTransferred: 2,
        totalFiles: 5,
        speed: 900,
      );

      expect(progress.currentFileFraction, 0.3);
      expect(progress.currentFileRemainingBytes, 700);
      expect(progress.overallFraction, 0.46);
      expect(progress.overallRemainingBytes, 2700);
      expect(progress.percent, 46);
      expect(progress.estimatedRemaining, const Duration(seconds: 3));
    });

    test('clamps over-reported byte counts', () {
      final progress = TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.inProgress,
        bytesTransferred: 1200,
        totalBytes: 1000,
        overallBytesTransferred: 6000,
        overallTotalBytes: 5000,
      );

      expect(progress.currentFileFraction, 1);
      expect(progress.currentFileRemainingBytes, 0);
      expect(progress.overallFraction, 1);
      expect(progress.overallRemainingBytes, 0);
    });
  });

  test('TransferRateTracker calculates a rolling byte rate', () {
    final tracker = TransferRateTracker(window: const Duration(seconds: 3));
    final start = DateTime.utc(2026, 1, 1);

    expect(tracker.addSample(0, timestamp: start), 0);
    expect(
      tracker.addSample(
        1_000_000,
        timestamp: start.add(const Duration(seconds: 1)),
      ),
      1_000_000,
    );
    expect(
      tracker.addSample(
        3_000_000,
        timestamp: start.add(const Duration(seconds: 3)),
      ),
      1_000_000,
    );
  });

  test('TransferRateTracker smooths sudden rate changes', () {
    final tracker = TransferRateTracker(
      window: const Duration(seconds: 4),
      smoothingFactor: 0.2,
    );
    final start = DateTime.utc(2026, 1, 1);

    tracker.addSample(0, timestamp: start);
    expect(
      tracker.addSample(
        1_000_000,
        timestamp: start.add(const Duration(seconds: 1)),
      ),
      1_000_000,
    );
    expect(
      tracker.addSample(
        6_000_000,
        timestamp: start.add(const Duration(seconds: 2)),
      ),
      1_400_000,
    );
  });

  test('copy publishes current-file and batch byte progress', () async {
    final source = MockStorageProvider();
    final destination = MockStorageProvider();
    final sourceDirectory = FileEntry(
      name: 'source',
      path: '/source',
      isDirectory: true,
    );
    final destinationDirectory = FileEntry(
      name: 'destination',
      path: '/destination',
      isDirectory: true,
    );
    final first = FileEntry(
      name: 'first.bin',
      path: '/source/first.bin',
      isDirectory: false,
      size: 1000,
    );
    final second = FileEntry(
      name: 'second.bin',
      path: '/source/second.bin',
      isDirectory: false,
      size: 3000,
    );
    source.seed(
      {
        sourceDirectory.path: sourceDirectory,
        first.path: first,
        second.path: second,
      },
      contents: {
        first.path: List<int>.filled(first.size, 1),
        second.path: List<int>.filled(second.size, 2),
      },
    );
    destination.seed({destinationDirectory.path: destinationDirectory});

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    await container
        .read(fileOperationsServiceProvider.notifier)
        .copy(
          sourceProvider: source,
          entries: [first, second],
          destProvider: destination,
          destPath: destinationDirectory.path,
        );

    final firstComplete = updates.firstWhere(
      (progress) =>
          progress.currentFile == first &&
          progress.bytesTransferred == first.size,
    );
    expect(firstComplete.totalBytes, first.size);
    expect(firstComplete.overallBytesTransferred, first.size);
    expect(firstComplete.overallTotalBytes, first.size + second.size);
    expect(firstComplete.filesTransferred, 1);
    expect(firstComplete.state, TransferState.inProgress);

    final completed = updates.last;
    expect(completed.state, TransferState.completed);
    expect(completed.overallBytesTransferred, first.size + second.size);
    expect(completed.overallTotalBytes, first.size + second.size);
    expect(completed.filesTransferred, 2);
    expect(completed.totalFiles, 2);
  });
  test('directory copy tracks each nested file and the batch total', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'fir-transfer-progress-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final sourceDirectory = Directory('${tempDirectory.path}/source')
      ..createSync();
    final destinationDirectory = Directory('${tempDirectory.path}/destination')
      ..createSync();
    File(
      '${sourceDirectory.path}/first.bin',
    ).writeAsBytesSync(List<int>.filled(2048, 1));
    final nestedDirectory = Directory('${sourceDirectory.path}/nested')
      ..createSync();
    File(
      '${nestedDirectory.path}/second.bin',
    ).writeAsBytesSync(List<int>.filled(4096, 2));

    final provider = LocalProvider(homePathOverride: tempDirectory.path);
    final sourceEntry = await provider.stat(sourceDirectory.path);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    await container
        .read(fileOperationsServiceProvider.notifier)
        .copy(
          sourceProvider: provider,
          entries: [sourceEntry],
          destProvider: provider,
          destPath: destinationDirectory.path,
        );

    final completed = updates.last;
    expect(completed.state, TransferState.completed);
    expect(completed.overallBytesTransferred, 6144);
    expect(completed.overallTotalBytes, 6144);
    expect(completed.filesTransferred, 2);
    expect(completed.totalFiles, 2);
    expect(
      updates
          .where((progress) => progress.currentFile != null)
          .map((progress) => progress.currentFile!.name),
      containsAll(['first.bin', 'second.bin']),
    );
    expect(
      File(
        '${destinationDirectory.path}/source/nested/second.bin',
      ).lengthSync(),
      4096,
    );
  });

  test('move publishes current-item and batch progress', () async {
    final provider = MockStorageProvider();
    final sourceDirectory = FileEntry(
      name: 'source',
      path: '/source',
      isDirectory: true,
    );
    final destinationDirectory = FileEntry(
      name: 'destination',
      path: '/destination',
      isDirectory: true,
    );
    final first = FileEntry(
      name: 'first.bin',
      path: '/source/first.bin',
      isDirectory: false,
      size: 1000,
    );
    final second = FileEntry(
      name: 'second.bin',
      path: '/source/second.bin',
      isDirectory: false,
      size: 3000,
    );
    provider.seed({
      sourceDirectory.path: sourceDirectory,
      destinationDirectory.path: destinationDirectory,
      first.path: first,
      second.path: second,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    await container
        .read(fileOperationsServiceProvider.notifier)
        .move(
          sourceProvider: provider,
          entries: [first, second],
          destProvider: provider,
          destPath: destinationDirectory.path,
        );

    final firstComplete = updates.firstWhere(
      (progress) =>
          progress.operation == TransferOperation.move &&
          progress.currentFile == first &&
          progress.bytesTransferred == first.size,
    );
    expect(firstComplete.totalBytes, first.size);
    expect(firstComplete.overallBytesTransferred, first.size);
    expect(firstComplete.overallTotalBytes, first.size + second.size);
    expect(firstComplete.filesTransferred, 1);
    expect(updates.last.state, TransferState.completed);
    expect(updates.last.overallBytesTransferred, first.size + second.size);
  });

  test('delete publishes current-item and batch progress', () async {
    final provider = MockStorageProvider();
    final root = FileEntry(name: 'root', path: '/root', isDirectory: true);
    final first = FileEntry(
      name: 'first.bin',
      path: '/root/first.bin',
      isDirectory: false,
      size: 1000,
    );
    final second = FileEntry(
      name: 'second.bin',
      path: '/root/second.bin',
      isDirectory: false,
      size: 3000,
    );
    provider.seed({root.path: root, first.path: first, second.path: second});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    await container
        .read(fileOperationsServiceProvider.notifier)
        .delete(provider: provider, entries: [first, second]);

    final firstComplete = updates.firstWhere(
      (progress) =>
          progress.operation == TransferOperation.delete &&
          progress.currentFile == first &&
          progress.bytesTransferred == first.size,
    );
    expect(firstComplete.totalBytes, first.size);
    expect(firstComplete.overallBytesTransferred, first.size);
    expect(firstComplete.overallTotalBytes, first.size + second.size);
    expect(firstComplete.filesTransferred, 1);
    expect(updates.last.state, TransferState.completed);
    expect(updates.last.overallBytesTransferred, first.size + second.size);
  });

  test(
    'sync analysis selects only missing or different source files',
    () async {
      final source = MockStorageProvider();
      final destination = MockStorageProvider();
      final sourceDirectory = FileEntry(
        name: 'source',
        path: '/source',
        isDirectory: true,
      );
      final destinationDirectory = FileEntry(
        name: 'destination',
        path: '/destination',
        isDirectory: true,
      );
      final timestamp = DateTime.utc(2026, 1, 1, 12);
      final equalSource = FileEntry(
        name: 'equal.bin',
        path: '/source/equal.bin',
        isDirectory: false,
        size: 100,
        modified: timestamp,
      );
      final differentSource = FileEntry(
        name: 'different.bin',
        path: '/source/different.bin',
        isDirectory: false,
        size: 200,
        modified: timestamp,
      );
      final missingSource = FileEntry(
        name: 'missing.bin',
        path: '/source/missing.bin',
        isDirectory: false,
        size: 300,
        modified: timestamp,
      );
      final equalDestination = equalSource.copyWith(
        path: '/destination/equal.bin',
      );
      final differentDestination = differentSource.copyWith(
        path: '/destination/different.bin',
        modified: timestamp.add(const Duration(minutes: 1)),
      );
      source.seed({
        sourceDirectory.path: sourceDirectory,
        equalSource.path: equalSource,
        differentSource.path: differentSource,
        missingSource.path: missingSource,
      });
      destination.seed({
        destinationDirectory.path: destinationDirectory,
        equalDestination.path: equalDestination,
        differentDestination.path: differentDestination,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final items = await container
          .read(fileOperationsServiceProvider.notifier)
          .analyzeSync(
            sourceProvider: source,
            sourcePath: sourceDirectory.path,
            destProvider: destination,
            destPath: destinationDirectory.path,
          );

      final byName = {for (final item in items) item.sourceEntry.name: item};
      expect(byName['equal.bin']?.status, SyncStatus.identical);
      expect(byName['equal.bin']?.isSelected, isFalse);
      expect(byName['equal.bin']?.destinationEntry, equalDestination);
      expect(byName['different.bin']?.status, SyncStatus.modified);
      expect(byName['different.bin']?.isSelected, isTrue);
      expect(byName['different.bin']?.destinationEntry, differentDestination);
      expect(byName['missing.bin']?.status, SyncStatus.missing);
      expect(byName['missing.bin']?.isSelected, isTrue);
      expect(byName['missing.bin']?.destinationEntry, isNull);
    },
  );

  test('sync publishes current-file and batch progress', () async {
    final source = MockStorageProvider();
    final destination = MockStorageProvider();
    final destinationDirectory = FileEntry(
      name: 'destination',
      path: '/destination',
      isDirectory: true,
    );
    final first = FileEntry(
      name: 'first.bin',
      path: '/source/first.bin',
      isDirectory: false,
      size: 1000,
    );
    final second = FileEntry(
      name: 'second.bin',
      path: '/source/second.bin',
      isDirectory: false,
      size: 3000,
    );
    final destinationSecond = second.copyWith(path: '/destination/second.bin');
    source.seed(
      {first.path: first, second.path: second},
      contents: {
        first.path: List<int>.filled(first.size, 1),
        second.path: List<int>.filled(second.size, 2),
      },
    );
    destination.seed({
      destinationDirectory.path: destinationDirectory,
      destinationSecond.path: destinationSecond,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    final result = await container
        .read(fileOperationsServiceProvider.notifier)
        .executeSync(
          sourceProvider: source,
          destProvider: destination,
          destPath: destinationDirectory.path,
          selectedItems: [
            SyncItem(
              sourceEntry: first,
              relativePath: first.name,
              depth: 0,
              status: SyncStatus.missing,
              isSelected: true,
            ),
            SyncItem(
              sourceEntry: second,
              destinationEntry: destinationSecond,
              relativePath: second.name,
              depth: 0,
              status: SyncStatus.modified,
              isSelected: true,
            ),
          ],
        );

    expect(
      updates.where(
        (progress) =>
            progress.operation == TransferOperation.sync &&
            progress.currentFile == first,
      ),
      isNotEmpty,
    );
    expect(updates.last.operation, TransferOperation.sync);
    expect(updates.last.state, TransferState.completed);
    expect(updates.last.overallBytesTransferred, first.size + second.size);
    expect(updates.last.overallTotalBytes, first.size + second.size);
    expect(updates.last.filesTransferred, 2);
    expect(updates.last.totalFiles, 2);
    expect(result.createdFiles, 1);
    expect(result.updatedFiles, 1);
    expect(result.failedFiles, 0);
    expect(result.cancelled, isFalse);
  });
  test('sync throttles high-frequency provider progress updates', () async {
    final source = _BurstProgressProvider();
    final destination = MockStorageProvider();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final updates = <TransferProgress>[];
    final subscription = container.listen<TransferProgress?>(
      operationProgressProvider,
      (_, next) {
        if (next != null) updates.add(next);
      },
    );
    addTearDown(subscription.close);

    final sourceEntry = FileEntry(
      name: 'large.bin',
      path: '/source/large.bin',
      isDirectory: false,
      size: 64 * 1024 * 256,
    );
    final result = await container
        .read(fileOperationsServiceProvider.notifier)
        .executeSync(
          sourceProvider: source,
          destProvider: destination,
          destPath: '/destination',
          selectedItems: [
            SyncItem(
              sourceEntry: sourceEntry,
              relativePath: sourceEntry.name,
              depth: 0,
              status: SyncStatus.missing,
              isSelected: true,
            ),
          ],
        );

    final syncUpdates = updates
        .where((progress) => progress.operation == TransferOperation.sync)
        .toList();
    expect(syncUpdates.length, lessThan(50));
    expect(syncUpdates.last.state, TransferState.completed);
    expect(result.createdFiles, 1);
    expect(result.failedFiles, 0);
  });

  test(
    'sync uses native local replace and preserves modification time',
    () async {
      final temporary = await Directory.systemTemp.createTemp('fir-fast-sync-');
      addTearDown(() => temporary.delete(recursive: true));
      final sourceDirectory = Directory('${temporary.path}/source')
        ..createSync();
      final destinationDirectory = Directory('${temporary.path}/destination')
        ..createSync();
      final modified = DateTime(2024, 4, 5, 6, 7, 8);
      final sourceFile = File('${sourceDirectory.path}/report.bin')
        ..writeAsBytesSync(
          List<int>.generate(1024 * 1024, (index) => index % 251),
        )
        ..setLastModifiedSync(modified);
      final destinationFile = File('${destinationDirectory.path}/report.bin')
        ..writeAsStringSync('old');
      final source = _TrackingLocalProvider();
      final destination = _TrackingLocalProvider();
      final sourceEntry = await source.stat(sourceFile.path);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(fileOperationsServiceProvider.notifier)
          .executeSync(
            sourceProvider: source,
            destProvider: destination,
            destPath: destinationDirectory.path,
            selectedItems: [
              SyncItem(
                sourceEntry: sourceEntry,
                destinationEntry: await destination.stat(destinationFile.path),
                relativePath: 'report.bin',
                depth: 0,
                status: SyncStatus.modified,
                isSelected: true,
              ),
            ],
          );

      expect(source.copyCalls, 0);
      expect(destination.copyCalls, 0);
      expect(destinationFile.readAsBytesSync(), sourceFile.readAsBytesSync());
      expect(
        destinationFile.lastModifiedSync().difference(modified).inSeconds,
        0,
      );
      expect(result.updatedFiles, 1);
      expect(result.transferredBytes, sourceEntry.size);
    },
  );

  test('sync verifies each destination directory only once', () async {
    final source = MockStorageProvider();
    final destination = _CountingMockStorageProvider();
    final destinationDirectory = FileEntry(
      name: 'destination',
      path: '/destination',
      isDirectory: true,
    );
    destination.seed({destinationDirectory.path: destinationDirectory});
    final items = <SyncItem>[];
    for (var index = 0; index < 10; index++) {
      final entry = FileEntry(
        name: '$index.bin',
        path: '/source/folder/$index.bin',
        isDirectory: false,
        size: 1,
      );
      source.addEntry(entry, content: [index]);
      items.add(
        SyncItem(
          sourceEntry: entry,
          relativePath: 'folder/${entry.name}',
          depth: 1,
          status: SyncStatus.missing,
          isSelected: true,
        ),
      );
    }
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container
        .read(fileOperationsServiceProvider.notifier)
        .executeSync(
          sourceProvider: source,
          destProvider: destination,
          destPath: destinationDirectory.path,
          selectedItems: items,
        );

    expect(destination.existsCalls['/destination'], 1);
    expect(destination.existsCalls['/destination/folder'], 1);
    expect(destination.mkdirCalls, ['/destination/folder']);
    expect(result.createdFiles, 10);
    expect(result.failedFiles, 0);
  });
}
