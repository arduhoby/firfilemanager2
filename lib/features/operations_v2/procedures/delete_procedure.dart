import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class DeleteOperationRequest implements OperationRequest {
  const DeleteOperationRequest({required this.providerId, required this.paths});

  @override
  String get type => DeleteProcedure.operationType;

  final String providerId;
  final List<String> paths;
}

class DeleteProcedure extends TypedOperationProcedure<DeleteOperationRequest> {
  const DeleteProcedure(super.executor);

  static const operationType = 'delete';

  @override
  String get type => operationType;
}
