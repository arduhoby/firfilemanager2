import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class EditFileCommand extends DelegatingFileCommand {
  EditFileCommand(CommandAction action)
    : super(
        id: CommandId.editFile,
        action: action,
        availability: CommandPredicates.hasFile,
      );
}
