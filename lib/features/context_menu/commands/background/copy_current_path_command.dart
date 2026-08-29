import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class CopyCurrentPathCommand extends DelegatingFileCommand {
  CopyCurrentPathCommand(CommandAction action)
    : super(
        id: CommandId.copyCurrentPath,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) =>
      context.currentPath.isEmpty
      ? const CommandAvailability.disabled('There is no path to copy.')
      : const CommandAvailability.available();
}
