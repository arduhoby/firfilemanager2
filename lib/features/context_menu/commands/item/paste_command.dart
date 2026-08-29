import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class PasteCommand extends DelegatingFileCommand {
  PasteCommand(CommandAction action)
    : super(id: CommandId.paste, action: action, availability: _availability);

  static CommandAvailability _availability(CommandContext context) {
    if (!context.hasClipboardEntries) {
      return const CommandAvailability.hidden('The clipboard is empty.');
    }
    return context.supports(CommandCapability.write)
        ? const CommandAvailability.available()
        : const CommandAvailability.disabled('The destination is read-only.');
  }
}
