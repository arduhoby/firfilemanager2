import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/multi_panel_transfer_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const third = PanelId('panel-3');
  const targets = [PanelId.b, third];
  const coordinator = MultiPanelTransferCoordinator();

  TransferProgress progress(TransferState state, {String? error}) =>
      TransferProgress(
        operation: TransferOperation.copy,
        state: state,
        error: error,
      );

  test(
    'copy visits every target in order and publishes one final completion',
    () async {
      final visited = <PanelId>[];
      final finalProgress = <TransferProgress>[];

      final result = await coordinator.execute(
        operation: TransferOperation.copy,
        targetPanelIds: targets,
        transferTarget: (panelId) async {
          visited.add(panelId);
          return progress(TransferState.completed);
        },
        publishFinalProgress: finalProgress.add,
      );

      expect(visited, targets);
      expect(result.isSuccessful, isTrue);
      expect(result.successfulPanelIds, targets);
      expect(finalProgress, hasLength(1));
      expect(finalProgress.single.state, TransferState.completed);
      expect(finalProgress.single.filesTransferred, 2);
      expect(finalProgress.single.totalFiles, 2);
    },
  );

  test(
    'compression visits every target and publishes one final completion',
    () async {
      final visited = <PanelId>[];
      final finalProgress = <TransferProgress>[];

      final result = await coordinator.execute(
        operation: TransferOperation.zip,
        targetPanelIds: targets,
        transferTarget: (panelId) async {
          visited.add(panelId);
          return TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.completed,
          );
        },
        publishFinalProgress: finalProgress.add,
      );

      expect(visited, targets);
      expect(result.isSuccessful, isTrue);
      expect(finalProgress, hasLength(1));
      expect(finalProgress.single.operation, TransferOperation.zip);
      expect(finalProgress.single.state, TransferState.completed);
    },
  );

  test('move preserves source when any target fails', () async {
    var deleteCalls = 0;
    final finalProgress = <TransferProgress>[];

    final result = await coordinator.execute(
      operation: TransferOperation.move,
      targetPanelIds: targets,
      transferTarget: (panelId) async => panelId == third
          ? progress(TransferState.failed, error: 'offline')
          : progress(TransferState.completed),
      deleteSource: () async => deleteCalls++,
      publishFinalProgress: finalProgress.add,
    );

    expect(result.successfulPanelIds, [PanelId.b]);
    expect(result.sourceDeleted, isFalse);
    expect(deleteCalls, 0);
    expect(finalProgress.single.state, TransferState.failed);
  });

  test('move deletes source once after all targets complete', () async {
    var deleteCalls = 0;
    final finalProgress = <TransferProgress>[];

    final result = await coordinator.execute(
      operation: TransferOperation.move,
      targetPanelIds: targets,
      transferTarget: (_) async => progress(TransferState.completed),
      deleteSource: () async => deleteCalls++,
      publishFinalProgress: finalProgress.add,
    );

    expect(deleteCalls, 1);
    expect(result.sourceDeleted, isTrue);
    expect(result.isSuccessful, isTrue);
    expect(finalProgress.single.state, TransferState.completed);
  });

  test(
    'cancellation skips remaining targets and never deletes source',
    () async {
      var deleteCalls = 0;
      final finalProgress = <TransferProgress>[];

      final result = await coordinator.execute(
        operation: TransferOperation.move,
        targetPanelIds: targets,
        transferTarget: (_) async => progress(TransferState.cancelled),
        deleteSource: () async => deleteCalls++,
        publishFinalProgress: finalProgress.add,
      );

      expect(result.targets.first.state, PanelTransferTargetState.cancelled);
      expect(result.targets.last.state, PanelTransferTargetState.skipped);
      expect(deleteCalls, 0);
      expect(finalProgress.single.state, TransferState.cancelled);
    },
  );

  test('source deletion failure produces a failed move result', () async {
    final finalProgress = <TransferProgress>[];

    final result = await coordinator.execute(
      operation: TransferOperation.move,
      targetPanelIds: targets,
      transferTarget: (_) async => progress(TransferState.completed),
      deleteSource: () async => throw StateError('delete failed'),
      publishFinalProgress: finalProgress.add,
    );

    expect(result.allTargetsSuccessful, isTrue);
    expect(result.sourceDeleted, isFalse);
    expect(result.sourceDeleteError, contains('delete failed'));
    expect(finalProgress.single.state, TransferState.failed);
  });
}
