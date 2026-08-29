import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class ExtractCommand extends DelegatingFileCommand {
  ExtractCommand(CommandAction action)
    : super(
        id: CommandId.extract,
        action: action,
        availability: CommandPredicates.hasFile,
      );
}
