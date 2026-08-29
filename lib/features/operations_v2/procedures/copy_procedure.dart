import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class CopyOperationRequest implements OperationRequest {
  const CopyOperationRequest({
    required this.sourceProviderId,
    required this.sourcePaths,
    required this.destinationProviderId,
    required this.destinationPath,
    this.verifyAfterCopy = true,
  });

  @override
  String get type => CopyProcedure.operationType;

  final String sourceProviderId;
  final List<String> sourcePaths;
  final String destinationProviderId;
  final String destinationPath;
  final bool verifyAfterCopy;
}

class CopyProcedure extends TypedOperationProcedure<CopyOperationRequest> {
  const CopyProcedure(super.executor);

  static const operationType = 'copy';

  @override
  String get type => operationType;
}
