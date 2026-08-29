import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CreateFolderCommand extends DelegatingFileCommand {
  CreateFolderCommand(CommandAction action)
    : super(
        id: CommandId.createFolder,
        action: action,
        availability: CommandPredicates.canWrite,
      );
}
