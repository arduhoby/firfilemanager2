import '../../../core/operations/operation_procedure.dart';
import '../../../core/operations/operation_request.dart';
import '../../../core/operations/operation_result.dart';

typedef TypedOperationExecutor<TRequest extends OperationRequest> =
    Future<OperationResult> Function(
      TRequest request,
      OperationExecutionScope scope,
    );

abstract class TypedOperationProcedure<TRequest extends OperationRequest>
    implements OperationProcedure {
  const TypedOperationProcedure(this._executor);

  final TypedOperationExecutor<TRequest> _executor;

  @override
  Future<OperationResult> execute(
    OperationRequest request,
    OperationExecutionScope scope,
  ) {
    if (request is! TRequest) {
      throw ArgumentError(
        '$type expected $TRequest but received ${request.runtimeType}.',
      );
    }
    return _executor(request, scope);
  }
}
