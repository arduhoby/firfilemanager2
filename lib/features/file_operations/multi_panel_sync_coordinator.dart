import 'package:flutter/foundation.dart';

import '../../core/storage/models/transfer_progress.dart';
import 'file_operations_state.dart';
import 'sync_models.dart';

enum PanelSyncTargetState { completed, noChanges, failed, cancelled, skipped }

@immutable
class PanelSyncTargetResult {
  const PanelSyncTargetResult({
    required this.panelId,
    required this.state,
    this.analyzedItems = 0,
    this.selectedItems = 0,
    this.execution,
    this.error,
  });

  final PanelId panelId;
  final PanelSyncTargetState state;
  final int analyzedItems;
  final int selectedItems;
  final SyncExecutionResult? execution;
  final String? error;

  bool get isSuccessful =>
      state == PanelSyncTargetState.completed ||
      state == PanelSyncTargetState.noChanges;
}

@immutable
class MultiPanelSyncResult {
  const MultiPanelSyncResult({required this.targets});

  final List<PanelSyncTargetResult> targets;

  int get successfulTargetCount =>
      targets.where((target) => target.isSuccessful).length;
  int get failedTargetCount => targets
      .where((target) => target.state == PanelSyncTargetState.failed)
      .length;
  int get totalSelectedFiles =>
      targets.fold(0, (sum, target) => sum + target.selectedItems);
  int get successfulFiles => targets.fold(
    0,
    (sum, target) => sum + (target.execution?.successfulFiles ?? 0),
  );
  bool get wasCancelled =>
      targets.any((target) => target.state == PanelSyncTargetState.cancelled);
  bool get isSuccessful =>
      targets.isNotEmpty && targets.every((target) => target.isSuccessful);
  List<PanelId> get refreshedPanelIds => targets
      .where((target) => target.state == PanelSyncTargetState.completed)
      .map((target) => target.panelId)
      .toList(growable: false);
}

typedef PanelSyncAnalyzer = Future<List<SyncItem>> Function(PanelId panelId);
typedef PanelSyncPreviewer =
    Future<List<SyncItem>?> Function(
      PanelId panelId,
      List<SyncItem> analyzedItems,
    );
typedef PanelSyncExecutor =
    Future<SyncExecutionResult> Function(
      PanelId panelId,
      List<SyncItem> selectedItems,
    );
typedef SyncFinalProgressPublisher = void Function(TransferProgress progress);

/// Coordinates multi-panel synchronization through three explicit phases:
/// analyze every target, preview every target, then execute sequentially.
class MultiPanelSyncCoordinator {
  const MultiPanelSyncCoordinator();

  Future<MultiPanelSyncResult> execute({
    required List<PanelId> targetPanelIds,
    required PanelSyncAnalyzer analyzeTarget,
    required PanelSyncPreviewer previewTarget,
    required PanelSyncExecutor executeTarget,
    required SyncFinalProgressPublisher publishFinalProgress,
  }) async {
    final analyzedByPanel = <PanelId, List<SyncItem>>{};
    final selectedByPanel = <PanelId, List<SyncItem>>{};
    final resultsByPanel = <PanelId, PanelSyncTargetResult>{};

    for (final panelId in targetPanelIds) {
      try {
        final items = await analyzeTarget(panelId);
        if (items.isEmpty) {
          resultsByPanel[panelId] = PanelSyncTargetResult(
            panelId: panelId,
            state: PanelSyncTargetState.noChanges,
          );
        } else {
          analyzedByPanel[panelId] = items;
        }
      } catch (error) {
        resultsByPanel[panelId] = PanelSyncTargetResult(
          panelId: panelId,
          state: PanelSyncTargetState.failed,
          error: error.toString(),
        );
      }
    }

    for (final panelId in targetPanelIds) {
      final analyzedItems = analyzedByPanel[panelId];
      if (analyzedItems == null) continue;

      try {
        final selectedItems = await previewTarget(panelId, analyzedItems);
        if (selectedItems == null) {
          resultsByPanel[panelId] = PanelSyncTargetResult(
            panelId: panelId,
            state: PanelSyncTargetState.cancelled,
            analyzedItems: analyzedItems.length,
          );
          for (final pendingId in targetPanelIds) {
            if (resultsByPanel.containsKey(pendingId)) continue;
            resultsByPanel[pendingId] = PanelSyncTargetResult(
              panelId: pendingId,
              state: PanelSyncTargetState.skipped,
              analyzedItems: analyzedByPanel[pendingId]?.length ?? 0,
            );
          }
          return _finish(targetPanelIds, resultsByPanel, publishFinalProgress);
        }

        if (selectedItems.isEmpty) {
          resultsByPanel[panelId] = PanelSyncTargetResult(
            panelId: panelId,
            state: PanelSyncTargetState.noChanges,
            analyzedItems: analyzedItems.length,
          );
        } else {
          selectedByPanel[panelId] = selectedItems;
        }
      } catch (error) {
        resultsByPanel[panelId] = PanelSyncTargetResult(
          panelId: panelId,
          state: PanelSyncTargetState.failed,
          analyzedItems: analyzedItems.length,
          error: error.toString(),
        );
      }
    }

    var cancelled = false;
    for (final panelId in targetPanelIds) {
      final selectedItems = selectedByPanel[panelId];
      if (selectedItems == null) continue;
      if (cancelled) {
        resultsByPanel[panelId] = PanelSyncTargetResult(
          panelId: panelId,
          state: PanelSyncTargetState.skipped,
          analyzedItems: analyzedByPanel[panelId]!.length,
          selectedItems: selectedItems.length,
        );
        continue;
      }

      try {
        final execution = await executeTarget(panelId, selectedItems);
        final state = execution.cancelled
            ? PanelSyncTargetState.cancelled
            : execution.failedFiles > 0
            ? PanelSyncTargetState.failed
            : PanelSyncTargetState.completed;
        resultsByPanel[panelId] = PanelSyncTargetResult(
          panelId: panelId,
          state: state,
          analyzedItems: analyzedByPanel[panelId]!.length,
          selectedItems: selectedItems.length,
          execution: execution,
          error: execution.failures.isEmpty
              ? null
              : execution.failures.first.message,
        );
        cancelled = execution.cancelled;
      } catch (error) {
        resultsByPanel[panelId] = PanelSyncTargetResult(
          panelId: panelId,
          state: PanelSyncTargetState.failed,
          analyzedItems: analyzedByPanel[panelId]!.length,
          selectedItems: selectedItems.length,
          error: error.toString(),
        );
      }
    }

    return _finish(targetPanelIds, resultsByPanel, publishFinalProgress);
  }

  MultiPanelSyncResult _finish(
    List<PanelId> targetPanelIds,
    Map<PanelId, PanelSyncTargetResult> resultsByPanel,
    SyncFinalProgressPublisher publishFinalProgress,
  ) {
    final targets = [
      for (final panelId in targetPanelIds)
        resultsByPanel[panelId] ??
            PanelSyncTargetResult(
              panelId: panelId,
              state: PanelSyncTargetState.skipped,
            ),
    ];
    final result = MultiPanelSyncResult(targets: List.unmodifiable(targets));
    final finalState = result.wasCancelled
        ? TransferState.cancelled
        : result.isSuccessful
        ? TransferState.completed
        : TransferState.failed;
    String? error;
    for (final target in targets) {
      if (target.error != null) {
        error = target.error;
        break;
      }
    }
    publishFinalProgress(
      TransferProgress(
        operation: TransferOperation.sync,
        state: finalState,
        filesTransferred: result.successfulFiles,
        totalFiles: result.totalSelectedFiles,
        error: error,
      ),
    );
    return result;
  }
}
