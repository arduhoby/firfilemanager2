import '../../../core/operations/operation_request.dart';
import 'typed_operation_procedure.dart';

class SyncOperationRequest implements OperationRequest {
  const SyncOperationRequest({
    required this.sourcePanelId,
    required this.targetPanelIds,
    required this.previewApproved,
  });

  @override
  String get type => SyncProcedure.operationType;

  final String sourcePanelId;
  final List<String> targetPanelIds;
  final bool previewApproved;
}

class SyncProcedure extends TypedOperationProcedure<SyncOperationRequest> {
  const SyncProcedure(super.executor);

  static const operationType = 'sync';

  @override
  String get type => operationType;
}
