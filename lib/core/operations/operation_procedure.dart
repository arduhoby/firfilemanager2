import 'cancellation_controller.dart';
import 'operation_event.dart';
import 'operation_id.dart';
import 'operation_request.dart';
import 'operation_result.dart';

typedef OperationEventEmitter = void Function(OperationEvent event);

class OperationExecutionScope {
  const OperationExecutionScope({
    required this.operationId,
    required this.cancellation,
    required OperationEventEmitter emit,
  }) : _emit = emit;

  final OperationId operationId;
  final CancellationController cancellation;
  final OperationEventEmitter _emit;

  void emit({
    required OperationPhase phase,
    required ProgressMetric metric,
    int? completedUnits,
    int? totalUnits,
    String? currentItem,
    String? message,
  }) {
    _emit(
      OperationEvent(
        operationId: operationId,
        phase: phase,
        metric: metric,
        completedUnits: completedUnits,
        totalUnits: totalUnits,
        currentItem: currentItem,
        message: message,
      ),
    );
  }
}

abstract interface class OperationProcedure {
  String get type;

  Future<OperationResult> execute(
    OperationRequest request,
    OperationExecutionScope scope,
  );
}
