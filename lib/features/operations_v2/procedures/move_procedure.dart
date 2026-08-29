import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class MoveOperationRequest implements OperationRequest {
  const MoveOperationRequest({
    required this.sourceProviderId,
    required this.sourcePaths,
    required this.destinationProviderId,
    required this.destinationPath,
  });

  @override
  String get type => MoveProcedure.operationType;

  final String sourceProviderId;
  final List<String> sourcePaths;
  final String destinationProviderId;
  final String destinationPath;
}

class MoveProcedure extends TypedOperationProcedure<MoveOperationRequest> {
  const MoveProcedure(super.executor);

  static const operationType = 'move';

  @override
  String get type => operationType;
}
