import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class RenameCommand extends DelegatingFileCommand {
  RenameCommand(CommandAction action)
    : super(id: CommandId.rename, action: action, availability: _availability);

  static CommandAvailability _availability(CommandContext context) {
    if (context.effectiveEntries.length != 1) {
      return const CommandAvailability.disabled(
        'Rename requires exactly one entry.',
      );
    }
    return context.supports(CommandCapability.rename)
        ? const CommandAvailability.available()
        : const CommandAvailability.disabled('Rename is not supported.');
  }
}
