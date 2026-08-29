import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class RenameOperationRequest implements OperationRequest {
  const RenameOperationRequest({
    required this.providerId,
    required this.path,
    required this.newName,
  });

  @override
  String get type => RenameProcedure.operationType;

  final String providerId;
  final String path;
  final String newName;
}

class RenameProcedure extends TypedOperationProcedure<RenameOperationRequest> {
  const RenameProcedure(super.executor);

  static const operationType = 'rename';

  @override
  String get type => operationType;
}
