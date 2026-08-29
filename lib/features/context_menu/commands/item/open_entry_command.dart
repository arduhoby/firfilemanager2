import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class OpenEntryCommand extends DelegatingFileCommand {
  OpenEntryCommand(CommandAction action)
    : super(
        id: CommandId.openEntry,
        action: action,
        availability: CommandPredicates.hasDirectory,
      );
}
