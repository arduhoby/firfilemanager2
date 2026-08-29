import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class OpenDefaultCommand extends DelegatingFileCommand {
  OpenDefaultCommand(CommandAction action)
    : super(
        id: CommandId.openDefault,
        action: action,
        availability: CommandPredicates.hasFile,
      );
}
