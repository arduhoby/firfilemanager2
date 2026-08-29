import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class OpenTerminalHereCommand extends DelegatingFileCommand {
  OpenTerminalHereCommand(CommandAction action)
    : super(
        id: CommandId.openTerminalHere,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) {
    final hasLocalPath =
        context.supports(CommandCapability.localPath) ||
        context.supports(CommandCapability.mountedPath);
    return hasLocalPath && context.supports(CommandCapability.terminal)
        ? const CommandAvailability.available()
        : const CommandAvailability.hidden(
            'Terminal is available only for local or mounted paths.',
          );
  }
}
