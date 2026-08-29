import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class QuickLookCommand extends DelegatingFileCommand {
  QuickLookCommand(CommandAction action)
    : super(
        id: CommandId.quickLook,
        action: action,
        availability: CommandPredicates.hasEntry,
      );
}
