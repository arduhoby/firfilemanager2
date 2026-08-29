import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class ShareSmbCommand extends DelegatingFileCommand {
  ShareSmbCommand(CommandAction action)
    : super(
        id: CommandId.shareSmb,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) =>
      context.clickedEntry != null && context.supports(CommandCapability.share)
      ? const CommandAvailability.available()
      : const CommandAvailability.hidden('SMB sharing is not available.');
}
