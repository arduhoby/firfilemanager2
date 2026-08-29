import '../../../core/commands/command_availability.dart';
import '../../../core/commands/command_context.dart';
import '../../../core/commands/command_id.dart';
import '../../../core/commands/command_result.dart';
import '../../../core/commands/file_command.dart';

typedef CommandAction = Future<CommandResult> Function(CommandContext context);
typedef CommandAvailabilityResolver =
    CommandAvailability Function(CommandContext context);

abstract class DelegatingFileCommand implements FileCommand {
  const DelegatingFileCommand({
    required this.id,
    required CommandAction action,
    required CommandAvailabilityResolver availability,
  }) : _action = action,
       _availability = availability;

  @override
  final CommandId id;
  final CommandAction _action;
  final CommandAvailabilityResolver _availability;

  @override
  CommandAvailability evaluate(CommandContext context) =>
      _availability(context);

  @override
  Future<CommandResult> execute(CommandContext context) => _action(context);
}
