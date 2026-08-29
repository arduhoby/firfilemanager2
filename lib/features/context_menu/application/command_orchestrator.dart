import '../../../core/commands/command_context.dart';
import '../../../core/commands/command_id.dart';
import '../../../core/commands/command_registry.dart';
import '../../../core/commands/command_result.dart';

typedef CommandReportCallback =
    Future<void> Function(
      CommandId id,
      CommandContext context,
      CommandResult result,
    );

class CommandOrchestrator {
  const CommandOrchestrator({
    required CommandRegistry registry,
    CommandReportCallback? report,
  }) : _registry = registry,
       _report = report;

  final CommandRegistry _registry;
  final CommandReportCallback? _report;

  Future<CommandResult> dispatch(CommandId id, CommandContext context) async {
    final command = _registry.resolve(id);
    final availability = command.evaluate(context);
    if (!availability.visible || !availability.enabled) {
      final result = CommandResult.rejected(
        availability.reason ?? 'Command is unavailable.',
      );
      await _report?.call(id, context, result);
      return result;
    }

    CommandResult result;
    try {
      result = await command.execute(context);
    } on Object catch (error) {
      result = CommandResult.failed(error);
    }
    await _report?.call(id, context, result);
    return result;
  }
}
