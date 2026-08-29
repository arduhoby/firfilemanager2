import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_service.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/storage/mock_storage_provider.dart';

void main() {
  test(
    'batch copy returns completion without publishing an intermediate completion',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final source = MockStorageProvider(displayName: 'Source');
      final destination = MockStorageProvider(displayName: 'Destination');
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        isDirectory: false,
        size: 4,
      );
      source.addEntry(entry, content: [1, 2, 3, 4]);

      final result = await container
          .read(fileOperationsServiceProvider.notifier)
          .copy(
            sourceProvider: source,
            entries: [entry],
            destProvider: destination,
            destPath: '/target',
            publishCompletion: false,
          );

      expect(result.state, TransferState.completed);
      expect(
        container.read(operationProgressProvider)?.state,
        TransferState.inProgress,
      );
      expect(await destination.exists('/target/file.txt'), isTrue);
    },
  );

  test(
    'move copy reports failure when a conflicting entry is skipped',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final source = MockStorageProvider(displayName: 'Source');
      final destination = MockStorageProvider(displayName: 'Destination');
      final entry = FileEntry(
        name: 'file.txt',
        path: '/file.txt',
        isDirectory: false,
        size: 4,
      );
      source.addEntry(entry, content: [1, 2, 3, 4]);
      destination.addEntry(
        entry.copyWith(path: '/target/file.txt'),
        content: [9],
      );

      final result = await container
          .read(fileOperationsServiceProvider.notifier)
          .copy(
            sourceProvider: source,
            entries: [entry],
            destProvider: destination,
            destPath: '/target',
            isMove: true,
            publishCompletion: false,
            overwriteCallback: (_) async => 'skip',
          );

      expect(result.state, TransferState.failed);
      expect(result.error, contains('skipped'));
      expect(await source.exists('/file.txt'), isTrue);
    },
  );

  test('batch sync suppresses its intermediate completion', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final source = MockStorageProvider(displayName: 'Source');
    final destination = MockStorageProvider(displayName: 'Destination');
    final entry = FileEntry(
      name: 'file.txt',
      path: '/source/file.txt',
      isDirectory: false,
      size: 4,
    );
    source.addEntry(entry, content: [1, 2, 3, 4]);
    destination.addEntry(
      FileEntry(name: 'target', path: '/target', isDirectory: true),
    );

    final result = await container
        .read(fileOperationsServiceProvider.notifier)
        .executeSync(
          sourceProvider: source,
          destProvider: destination,
          destPath: '/target',
          selectedItems: [
            SyncItem(
              sourceEntry: entry,
              relativePath: entry.name,
              depth: 0,
              status: SyncStatus.missing,
              isSelected: true,
            ),
          ],
          publishCompletion: false,
        );

    expect(result.createdFiles, 1);
    expect(result.failedFiles, 0);
    expect(
      container.read(operationProgressProvider)?.state,
      TransferState.inProgress,
    );
    expect(
      container.read(operationProgressProvider)?.operation,
      TransferOperation.sync,
    );
  });
}
