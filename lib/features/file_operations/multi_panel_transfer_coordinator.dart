import 'package:flutter/foundation.dart';

import '../../core/storage/models/transfer_progress.dart';
import 'file_operations_state.dart';

enum PanelTransferTargetState { completed, failed, cancelled, skipped }

@immutable
class PanelTransferTargetResult {
  const PanelTransferTargetResult({
    required this.panelId,
    required this.state,
    this.error,
  });

  final PanelId panelId;
  final PanelTransferTargetState state;
  final String? error;

  bool get isSuccessful => state == PanelTransferTargetState.completed;
}

@immutable
class MultiPanelTransferResult {
  const MultiPanelTransferResult({
    required this.operation,
    required this.targets,
    required this.sourceDeleted,
    this.sourceDeleteError,
  });

  final TransferOperation operation;
  final List<PanelTransferTargetResult> targets;
  final bool sourceDeleted;
  final String? sourceDeleteError;

  List<PanelId> get successfulPanelIds => targets
      .where((target) => target.isSuccessful)
      .map((target) => target.panelId)
      .toList(growable: false);

  int get successfulTargetCount => successfulPanelIds.length;
  int get unsuccessfulTargetCount => targets.length - successfulTargetCount;
  bool get wasCancelled => targets.any(
    (target) => target.state == PanelTransferTargetState.cancelled,
  );
  bool get allTargetsSuccessful =>
      targets.isNotEmpty && targets.every((target) => target.isSuccessful);
  bool get isSuccessful =>
      allTargetsSuccessful &&
      (operation != TransferOperation.move || sourceDeleted);
}

typedef PanelTargetTransfer =
    Future<TransferProgress> Function(PanelId panelId);
typedef SourceDelete = Future<void> Function();
typedef FinalProgressPublisher = void Function(TransferProgress progress);

/// Executes one source operation against several destination panels
/// sequentially.
///
/// Sequential execution keeps the existing single progress channel coherent.
/// Move deletes the source only after every destination reports completion.
class MultiPanelTransferCoordinator {
  const MultiPanelTransferCoordinator();

  Future<MultiPanelTransferResult> execute({
    required TransferOperation operation,
    required List<PanelId> targetPanelIds,
    required PanelTargetTransfer transferTarget,
    required FinalProgressPublisher publishFinalProgress,
    SourceDelete? deleteSource,
  }) async {
    assert(
      operation == TransferOperation.copy ||
          operation == TransferOperation.move ||
          operation == TransferOperation.zip,
    );

    final targetResults = <PanelTransferTargetResult>[];
    var cancelled = false;

    for (final panelId in targetPanelIds) {
      if (cancelled) {
        targetResults.add(
          PanelTransferTargetResult(
            panelId: panelId,
            state: PanelTransferTargetState.skipped,
          ),
        );
        continue;
      }

      try {
        final progress = await transferTarget(panelId);
        final state = switch (progress.state) {
          TransferState.completed => PanelTransferTargetState.completed,
          TransferState.cancelled => PanelTransferTargetState.cancelled,
          _ => PanelTransferTargetState.failed,
        };
        targetResults.add(
          PanelTransferTargetResult(
            panelId: panelId,
            state: state,
            error: progress.error,
          ),
        );
        cancelled = state == PanelTransferTargetState.cancelled;
      } catch (error) {
        targetResults.add(
          PanelTransferTargetResult(
            panelId: panelId,
            state: PanelTransferTargetState.failed,
            error: error.toString(),
          ),
        );
      }
    }

    final everyTargetSucceeded =
        targetResults.length == targetPanelIds.length &&
        targetResults.every((target) => target.isSuccessful);
    var sourceDeleted = false;
    String? sourceDeleteError;

    if (operation == TransferOperation.move && everyTargetSucceeded) {
      try {
        if (deleteSource == null) {
          throw StateError('Move requires a source delete callback.');
        }
        await deleteSource();
        sourceDeleted = true;
      } catch (error) {
        sourceDeleteError = error.toString();
      }
    }

    final result = MultiPanelTransferResult(
      operation: operation,
      targets: List.unmodifiable(targetResults),
      sourceDeleted: sourceDeleted,
      sourceDeleteError: sourceDeleteError,
    );
    final finalState = result.wasCancelled
        ? TransferState.cancelled
        : result.isSuccessful
        ? TransferState.completed
        : TransferState.failed;
    String? firstTargetError;
    for (final target in targetResults) {
      if (target.error != null) {
        firstTargetError = target.error;
        break;
      }
    }
    publishFinalProgress(
      TransferProgress(
        operation: operation,
        state: finalState,
        filesTransferred: result.successfulTargetCount,
        totalFiles: targetPanelIds.length,
        error: sourceDeleteError ?? firstTargetError,
      ),
    );
    return result;
  }
}
