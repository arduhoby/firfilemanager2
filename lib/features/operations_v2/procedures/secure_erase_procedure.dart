import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class SecureEraseOperationRequest implements OperationRequest {
  const SecureEraseOperationRequest({required this.localPaths, this.passes = 1})
    : assert(passes > 0);

  @override
  String get type => SecureEraseProcedure.operationType;

  final List<String> localPaths;
  final int passes;
}

class SecureEraseProcedure
    extends TypedOperationProcedure<SecureEraseOperationRequest> {
  const SecureEraseProcedure(super.executor);

  static const operationType = 'secure-erase';

  @override
  String get type => operationType;
}
