import 'dart:async';

import 'cancellation_controller.dart';
import 'operation_event.dart';
import 'operation_id.dart';
import 'operation_result.dart';

class OperationHandle {
  const OperationHandle({
    required this.id,
    required this.events,
    required this.result,
    required CancellationController cancellation,
  }) : _cancellation = cancellation;

  final OperationId id;
  final Stream<OperationEvent> events;
  final Future<OperationResult> result;
  final CancellationController _cancellation;

  bool get cancellationRequested => _cancellation.isCancelled;

  void cancel() => _cancellation.cancel();
}
