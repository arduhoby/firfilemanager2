import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class CreateFileOperationRequest implements OperationRequest {
  const CreateFileOperationRequest({
    required this.providerId,
    required this.parentPath,
    required this.name,
  });

  @override
  String get type => CreateFileProcedure.operationType;

  final String providerId;
  final String parentPath;
  final String name;
}

class CreateFileProcedure
    extends TypedOperationProcedure<CreateFileOperationRequest> {
  const CreateFileProcedure(super.executor);

  static const operationType = 'create-file';

  @override
  String get type => operationType;
}
