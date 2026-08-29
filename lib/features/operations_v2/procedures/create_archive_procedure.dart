import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

enum ArchiveOutputFormat { zip, tar, tarGz, passwordZip }

class CreateArchiveOperationRequest implements OperationRequest {
  const CreateArchiveOperationRequest({
    required this.providerId,
    required this.sourcePaths,
    required this.destinationPaths,
    required this.format,
    this.password,
  });

  @override
  String get type => CreateArchiveProcedure.operationType;

  final String providerId;
  final List<String> sourcePaths;
  final List<String> destinationPaths;
  final ArchiveOutputFormat format;
  final String? password;
}

class CreateArchiveProcedure
    extends TypedOperationProcedure<CreateArchiveOperationRequest> {
  const CreateArchiveProcedure(super.executor);

  static const operationType = 'create-archive';

  @override
  String get type => operationType;
}
