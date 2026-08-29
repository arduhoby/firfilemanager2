import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class RevealCurrentFolderCommand extends DelegatingFileCommand {
  RevealCurrentFolderCommand(CommandAction action)
    : super(
        id: CommandId.revealCurrentFolder,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) =>
      context.currentPath.isEmpty
      ? const CommandAvailability.disabled('There is no folder to reveal.')
      : const CommandAvailability.available();
}
