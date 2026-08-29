import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CreateFileCommand extends DelegatingFileCommand {
  CreateFileCommand(CommandAction action)
    : super(
        id: CommandId.createFile,
        action: action,
        availability: CommandPredicates.canWrite,
      );
}
