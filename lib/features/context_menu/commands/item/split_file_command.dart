import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class SplitFileCommand extends DelegatingFileCommand {
  SplitFileCommand(CommandAction action)
    : super(
        id: CommandId.splitFile,
        action: action,
        availability: CommandPredicates.canSplitFile,
      );
}
