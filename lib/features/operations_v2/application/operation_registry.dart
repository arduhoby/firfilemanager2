import '../../../core/operations/operation_procedure.dart';

class OperationRegistry {
  OperationRegistry(Iterable<OperationProcedure> procedures)
    : _procedures = <String, OperationProcedure>{
        for (final procedure in procedures) procedure.type: procedure,
      } {
    if (_procedures.length != procedures.length) {
      throw ArgumentError('Every operation type must have exactly one owner.');
    }
  }

  final Map<String, OperationProcedure> _procedures;

  OperationProcedure resolve(String type) {
    final procedure = _procedures[type];
    if (procedure == null) {
      throw StateError('No operation procedure registered for $type.');
    }
    return procedure;
  }
}
