import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CopySelectionCommand extends DelegatingFileCommand {
  CopySelectionCommand(CommandAction action)
    : super(
        id: CommandId.copySelection,
        action: action,
        availability: CommandPredicates.hasEffectiveEntries,
      );
}
