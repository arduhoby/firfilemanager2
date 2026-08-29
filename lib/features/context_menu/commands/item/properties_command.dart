import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class PropertiesCommand extends DelegatingFileCommand {
  PropertiesCommand(CommandAction action)
    : super(
        id: CommandId.properties,
        action: action,
        availability: CommandPredicates.hasEntry,
      );
}
