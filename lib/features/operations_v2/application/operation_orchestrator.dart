import 'dart:async';

import '../../../core/operations/cancellation_controller.dart';
import '../../../core/operations/operation_event.dart';
import '../../../core/operations/operation_handle.dart';
import '../../../core/operations/operation_id.dart';
import '../../../core/operations/operation_procedure.dart';
import '../../../core/operations/operation_request.dart';
import '../../../core/operations/operation_result.dart';
import 'operation_registry.dart';
import 'operation_reporter.dart';
import 'operation_verifier.dart';

class OperationOrchestrator {
  OperationOrchestrator({
    required OperationRegistry registry,
    OperationVerifier verifier = const PassThroughOperationVerifier(),
    OperationReporter reporter = const NoOpOperationReporter(),
  }) : _registry = registry,
       _verifier = verifier,
       _reporter = reporter;

  final OperationRegistry _registry;
  final OperationVerifier _verifier;
  final OperationReporter _reporter;
  final Map<OperationId, CancellationController> _active =
      <OperationId, CancellationController>{};
  int _sequence = 0;

  Set<OperationId> get activeOperationIds =>
      Set<OperationId>.unmodifiable(_active.keys);

  OperationHandle start(OperationRequest request) {
    final operationId = OperationId(
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
    );
    final cancellation = CancellationController();
    // Closed by _run after the procedure, verification and reporting finish.
    // ignore: close_sinks
    final events = StreamController<OperationEvent>.broadcast();
    final result = Completer<OperationResult>();
    _active[operationId] = cancellation;

    final handle = OperationHandle(
      id: operationId,
      events: events.stream,
      result: result.future,
      cancellation: cancellation,
    );
    unawaited(
      Future<void>.microtask(
        () => _run(
          operationId: operationId,
          request: request,
          cancellation: cancellation,
          events: events,
          result: result,
        ),
      ),
    );
    return handle;
  }

  bool cancel(OperationId operationId) {
    final cancellation = _active[operationId];
    if (cancellation == null) return false;
    cancellation.cancel();
    return true;
  }

  Future<void> _run({
    required OperationId operationId,
    required OperationRequest request,
    required CancellationController cancellation,
    required StreamController<OperationEvent> events,
    required Completer<OperationResult> result,
  }) async {
    events.add(
      OperationEvent(
        operationId: operationId,
        phase: OperationPhase.queued,
        metric: ProgressMetric.indeterminate,
      ),
    );

    OperationResult finalResult;
    try {
      final procedure = _registry.resolve(request.type);
      final procedureResult = await procedure.execute(
        request,
        OperationExecutionScope(
          operationId: operationId,
          cancellation: cancellation,
          emit: events.add,
        ),
      );
      finalResult = cancellation.isCancelled
          ? OperationResult.cancelled(operationId)
          : await _verifier.verify(request, procedureResult);
    } on OperationCancelledException {
      finalResult = OperationResult.cancelled(operationId);
    } on Object catch (error) {
      finalResult = OperationResult.failed(operationId, error);
    }

    final terminalPhase = switch (finalResult.state) {
      OperationResultState.completed => OperationPhase.completed,
      OperationResultState.cancelled => OperationPhase.cancelled,
      OperationResultState.failed => OperationPhase.failed,
    };
    events.add(
      OperationEvent(
        operationId: operationId,
        phase: terminalPhase,
        metric: ProgressMetric.indeterminate,
        message: finalResult.message,
      ),
    );
    await _reporter.report(request, finalResult);
    _active.remove(operationId);
    result.complete(finalResult);
    await events.close();
  }
}
