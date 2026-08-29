import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class MoveSelectionCommand extends DelegatingFileCommand {
  MoveSelectionCommand(CommandAction action)
    : super(
        id: CommandId.moveSelection,
        action: action,
        availability: CommandPredicates.hasEffectiveEntries,
      );
}
