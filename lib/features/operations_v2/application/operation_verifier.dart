import '../../../core/operations/operation_request.dart';
import '../../../core/operations/operation_result.dart';

abstract interface class OperationVerifier {
  Future<OperationResult> verify(
    OperationRequest request,
    OperationResult result,
  );
}

class PassThroughOperationVerifier implements OperationVerifier {
  const PassThroughOperationVerifier();

  @override
  Future<OperationResult> verify(
    OperationRequest request,
    OperationResult result,
  ) async => result;
}
