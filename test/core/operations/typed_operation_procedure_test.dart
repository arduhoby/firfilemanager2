import 'package:fir_file_manager/core/operations/cancellation_controller.dart';
import 'package:fir_file_manager/core/operations/operation_id.dart';
import 'package:fir_file_manager/core/operations/operation_procedure.dart';
import 'package:fir_file_manager/core/operations/operation_result.dart';
import 'package:fir_file_manager/features/operations_v2/procedures/delete_procedure.dart';
import 'package:fir_file_manager/features/operations_v2/procedures/secure_erase_procedure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normal delete and secure erase have separate procedure owners', () {
    final delete = DeleteProcedure(
      (request, scope) async => OperationResult.completed(scope.operationId),
    );
    final secureErase = SecureEraseProcedure(
      (request, scope) async => OperationResult.completed(scope.operationId),
    );

    expect(delete.type, 'delete');
    expect(secureErase.type, 'secure-erase');
    expect(delete.type, isNot(secureErase.type));
  });

  test('typed procedure rejects the wrong request contract', () async {
    final delete = DeleteProcedure(
      (request, scope) async => OperationResult.completed(scope.operationId),
    );
    const wrongRequest = SecureEraseOperationRequest(localPaths: <String>[]);
    final scope = OperationExecutionScope(
      operationId: const OperationId('test'),
      cancellation: CancellationController(),
      emit: (_) {},
    );

    expect(() => delete.execute(wrongRequest, scope), throwsArgumentError);
  });
}
