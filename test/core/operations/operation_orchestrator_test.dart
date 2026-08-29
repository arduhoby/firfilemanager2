import 'dart:async';

import 'package:fir_file_manager/core/operations/operation_event.dart';
import 'package:fir_file_manager/core/operations/operation_procedure.dart';
import 'package:fir_file_manager/core/operations/operation_request.dart';
import 'package:fir_file_manager/core/operations/operation_result.dart';
import 'package:fir_file_manager/features/operations_v2/application/operation_orchestrator.dart';
import 'package:fir_file_manager/features/operations_v2/application/operation_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelling one operation does not cancel another operation', () async {
    final procedure = _ControlledProcedure();
    final orchestrator = OperationOrchestrator(
      registry: OperationRegistry(<OperationProcedure>[procedure]),
    );
    final first = orchestrator.start(const _Request());
    final second = orchestrator.start(const _Request());

    await procedure.waitUntilPending(2);
    first.cancel();
    procedure.completePending();

    final firstResult = await first.result;
    final secondResult = await second.result;
    expect(firstResult.state, OperationResultState.cancelled);
    expect(secondResult.state, OperationResultState.completed);
    expect(first.id, isNot(second.id));
  });

  test('each operation publishes its own terminal event', () async {
    final orchestrator = OperationOrchestrator(
      registry: OperationRegistry(<OperationProcedure>[
        const _ImmediateProcedure(),
      ]),
    );
    final handle = orchestrator.start(const _Request());
    final events = <OperationEvent>[];
    final subscription = handle.events.listen(events.add);

    final result = await handle.result;
    await subscription.cancel();

    expect(result.state, OperationResultState.completed);
    expect(events.first.phase, OperationPhase.queued);
    expect(events.last.phase, OperationPhase.completed);
    expect(events.every((event) => event.operationId == handle.id), isTrue);
  });
}

class _Request implements OperationRequest {
  const _Request();

  @override
  String get type => 'test';
}

class _ImmediateProcedure implements OperationProcedure {
  const _ImmediateProcedure();

  @override
  String get type => 'test';

  @override
  Future<OperationResult> execute(
    OperationRequest request,
    OperationExecutionScope scope,
  ) async {
    scope.emit(
      phase: OperationPhase.verifying,
      metric: ProgressMetric.phases,
      completedUnits: 1,
      totalUnits: 1,
    );
    return OperationResult.completed(scope.operationId);
  }
}

class _ControlledProcedure implements OperationProcedure {
  final List<Completer<void>> _pending = <Completer<void>>[];
  final Completer<void> _twoPending = Completer<void>();

  @override
  String get type => 'test';

  @override
  Future<OperationResult> execute(
    OperationRequest request,
    OperationExecutionScope scope,
  ) async {
    final completer = Completer<void>();
    _pending.add(completer);
    if (_pending.length >= 2 && !_twoPending.isCompleted) {
      _twoPending.complete();
    }
    await completer.future;
    scope.cancellation.throwIfCancelled();
    return OperationResult.completed(scope.operationId);
  }

  void completePending() {
    for (final completer in List<Completer<void>>.of(_pending)) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> waitUntilPending(int count) {
    if (_pending.length >= count) return Future<void>.value();
    return _twoPending.future;
  }
}
