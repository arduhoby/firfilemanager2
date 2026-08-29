import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class RevealCommand extends DelegatingFileCommand {
  RevealCommand(CommandAction action)
    : super(
        id: CommandId.reveal,
        action: action,
        availability: CommandPredicates.hasEntry,
      );
}
