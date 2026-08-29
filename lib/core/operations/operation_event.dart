import 'operation_id.dart';

enum OperationPhase {
  queued,
  scanning,
  preparing,
  transferring,
  encoding,
  verifying,
  finalizing,
  cancelling,
  completed,
  cancelled,
  failed,
}

enum ProgressMetric { bytes, items, phases, indeterminate }

class OperationEvent {
  const OperationEvent({
    required this.operationId,
    required this.phase,
    required this.metric,
    this.completedUnits,
    this.totalUnits,
    this.currentItem,
    this.message,
  });

  final OperationId operationId;
  final OperationPhase phase;
  final ProgressMetric metric;
  final int? completedUnits;
  final int? totalUnits;
  final String? currentItem;
  final String? message;

  bool get isTerminal =>
      phase == OperationPhase.completed ||
      phase == OperationPhase.cancelled ||
      phase == OperationPhase.failed;
}
