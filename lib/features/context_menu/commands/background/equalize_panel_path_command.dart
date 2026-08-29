import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class EqualizePanelPathCommand extends DelegatingFileCommand {
  EqualizePanelPathCommand(CommandAction action)
    : super(
        id: CommandId.equalizePanelPath,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) =>
      context.targetPanelIds.isEmpty
      ? const CommandAvailability.disabled('There is no other panel.')
      : const CommandAvailability.available();
}
