import 'operation_id.dart';

enum OperationResultState { completed, cancelled, failed }

class OperationResult {
  const OperationResult._({
    required this.operationId,
    required this.state,
    this.message,
    this.error,
  });

  const OperationResult.completed(OperationId id, [String? message])
    : this._(
        operationId: id,
        state: OperationResultState.completed,
        message: message,
      );

  const OperationResult.cancelled(OperationId id, [String? message])
    : this._(
        operationId: id,
        state: OperationResultState.cancelled,
        message: message,
      );

  const OperationResult.failed(OperationId id, Object error)
    : this._(operationId: id, state: OperationResultState.failed, error: error);

  final OperationId operationId;
  final OperationResultState state;
  final String? message;
  final Object? error;

  bool get succeeded => state == OperationResultState.completed;
}
