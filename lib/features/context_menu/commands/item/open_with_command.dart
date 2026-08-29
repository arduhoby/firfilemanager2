import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class OpenWithCommand extends DelegatingFileCommand {
  OpenWithCommand(CommandAction action)
    : super(
        id: CommandId.openWith,
        action: action,
        availability: CommandPredicates.hasFile,
      );
}
