import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../command_action.dart';

class SecureEraseCommand extends DelegatingFileCommand {
  SecureEraseCommand(CommandAction action)
    : super(
        id: CommandId.secureErase,
        action: action,
        availability: _availability,
      );

  static CommandAvailability _availability(CommandContext context) {
    final local = context.supports(CommandCapability.localPath);
    final deletable = context.supports(CommandCapability.delete);
    final filesOnly =
        context.effectiveEntries.isNotEmpty &&
        context.effectiveEntries.every((entry) => !entry.isDirectory);
    return local && deletable && filesOnly
        ? const CommandAvailability.available()
        : const CommandAvailability.hidden(
            'Secure erase requires local files.',
          );
  }
}
