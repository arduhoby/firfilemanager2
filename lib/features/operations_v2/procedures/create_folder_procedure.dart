import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class CreateFolderOperationRequest implements OperationRequest {
  const CreateFolderOperationRequest({
    required this.providerId,
    required this.parentPath,
    required this.name,
  });

  @override
  String get type => CreateFolderProcedure.operationType;

  final String providerId;
  final String parentPath;
  final String name;
}

class CreateFolderProcedure
    extends TypedOperationProcedure<CreateFolderOperationRequest> {
  const CreateFolderProcedure(super.executor);

  static const operationType = 'create-folder';

  @override
  String get type => operationType;
}
