import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/multi_panel_sync_coordinator.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const third = PanelId('panel-3');

  SyncItem item(String name) => SyncItem(
    sourceEntry: FileEntry(
      name: name,
      path: '/source/$name',
      isDirectory: false,
      size: 1,
    ),
    relativePath: name,
    depth: 0,
    status: SyncStatus.missing,
    isSelected: true,
  );

  SyncExecutionResult success(int count) => SyncExecutionResult(
    createdFiles: count,
    updatedFiles: 0,
    failedFiles: 0,
    cancelled: false,
  );

  test(
    'analyzes and previews every target before executing in order',
    () async {
      final events = <String>[];
      final published = <TransferProgress>[];

      final result = await const MultiPanelSyncCoordinator().execute(
        targetPanelIds: const [PanelId.b, third],
        analyzeTarget: (panelId) async {
          events.add('analyze:${panelId.value}');
          return [item('${panelId.value}.txt')];
        },
        previewTarget: (panelId, items) async {
          events.add('preview:${panelId.value}:${items.single.relativePath}');
          return items;
        },
        executeTarget: (panelId, items) async {
          events.add('execute:${panelId.value}:${items.single.relativePath}');
          return success(items.length);
        },
        publishFinalProgress: published.add,
      );

      expect(events, [
        'analyze:panel-b',
        'analyze:panel-3',
        'preview:panel-b:panel-b.txt',
        'preview:panel-3:panel-3.txt',
        'execute:panel-b:panel-b.txt',
        'execute:panel-3:panel-3.txt',
      ]);
      expect(result.targets.every((target) => target.isSuccessful), isTrue);
      expect(published, hasLength(1));
      expect(published.single.state, TransferState.completed);
      expect(published.single.filesTransferred, 2);
      expect(published.single.totalFiles, 2);
    },
  );

  test('keeps no-change and analysis-failure results independent', () async {
    var executeCount = 0;
    final published = <TransferProgress>[];

    final result = await const MultiPanelSyncCoordinator().execute(
      targetPanelIds: const [PanelId.b, third],
      analyzeTarget: (panelId) async {
        if (panelId == PanelId.b) return [];
        throw StateError('offline');
      },
      previewTarget: (_, items) async => items,
      executeTarget: (_, items) async {
        executeCount++;
        return success(items.length);
      },
      publishFinalProgress: published.add,
    );

    expect(result.targets[0].state, PanelSyncTargetState.noChanges);
    expect(result.targets[1].state, PanelSyncTargetState.failed);
    expect(result.targets[1].error, contains('offline'));
    expect(executeCount, 0);
    expect(published.single.state, TransferState.failed);
  });

  test('preview cancellation prevents every target execution', () async {
    var executeCount = 0;
    final published = <TransferProgress>[];

    final result = await const MultiPanelSyncCoordinator().execute(
      targetPanelIds: const [PanelId.b, third],
      analyzeTarget: (panelId) async => [item('${panelId.value}.txt')],
      previewTarget: (panelId, items) async => panelId == third ? null : items,
      executeTarget: (_, items) async {
        executeCount++;
        return success(items.length);
      },
      publishFinalProgress: published.add,
    );

    expect(executeCount, 0);
    expect(result.targets[0].state, PanelSyncTargetState.skipped);
    expect(result.targets[1].state, PanelSyncTargetState.cancelled);
    expect(published.single.state, TransferState.cancelled);
  });

  test(
    'continues with independent targets after one execution fails',
    () async {
      final executed = <PanelId>[];
      final published = <TransferProgress>[];

      final result = await const MultiPanelSyncCoordinator().execute(
        targetPanelIds: const [PanelId.b, third],
        analyzeTarget: (panelId) async => [item('${panelId.value}.txt')],
        previewTarget: (_, items) async => items,
        executeTarget: (panelId, items) async {
          executed.add(panelId);
          if (panelId == PanelId.b) {
            return const SyncExecutionResult(
              createdFiles: 0,
              updatedFiles: 0,
              failedFiles: 1,
              cancelled: false,
              failures: [
                SyncFileFailure(
                  relativePath: 'bad.txt',
                  message: 'write failed',
                ),
              ],
            );
          }
          return success(items.length);
        },
        publishFinalProgress: published.add,
      );

      expect(executed, const [PanelId.b, third]);
      expect(result.targets[0].state, PanelSyncTargetState.failed);
      expect(result.targets[1].state, PanelSyncTargetState.completed);
      expect(published, hasLength(1));
      expect(published.single.state, TransferState.failed);
    },
  );
}
