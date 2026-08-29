import '../../../core/operations/operation_request.dart';
import '../../../core/operations/operation_result.dart';

abstract interface class OperationReporter {
  Future<void> report(OperationRequest request, OperationResult result);
}

class NoOpOperationReporter implements OperationReporter {
  const NoOpOperationReporter();

  @override
  Future<void> report(OperationRequest request, OperationResult result) async {}
}
