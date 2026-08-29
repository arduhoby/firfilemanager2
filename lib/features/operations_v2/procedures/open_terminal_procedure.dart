import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class OpenTerminalOperationRequest implements OperationRequest {
  const OpenTerminalOperationRequest({required this.localPath});

  @override
  String get type => OpenTerminalProcedure.operationType;

  final String localPath;
}

class OpenTerminalProcedure
    extends TypedOperationProcedure<OpenTerminalOperationRequest> {
  const OpenTerminalProcedure(super.executor);

  static const operationType = 'open-terminal';

  @override
  String get type => operationType;
}
