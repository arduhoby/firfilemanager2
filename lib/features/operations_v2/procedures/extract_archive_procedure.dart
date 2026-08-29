import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class ExtractArchiveOperationRequest implements OperationRequest {
  const ExtractArchiveOperationRequest({
    required this.providerId,
    required this.archivePath,
    required this.destinationPath,
    this.password,
  });

  @override
  String get type => ExtractArchiveProcedure.operationType;

  final String providerId;
  final String archivePath;
  final String destinationPath;
  final String? password;
}

class ExtractArchiveProcedure
    extends TypedOperationProcedure<ExtractArchiveOperationRequest> {
  const ExtractArchiveProcedure(super.executor);

  static const operationType = 'extract-archive';

  @override
  String get type => operationType;
}
