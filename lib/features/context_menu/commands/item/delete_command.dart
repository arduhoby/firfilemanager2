import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class DeleteCommand extends DelegatingFileCommand {
  DeleteCommand(CommandAction action)
    : super(
        id: CommandId.delete,
        action: action,
        availability: CommandPredicates.canDelete,
      );
}
