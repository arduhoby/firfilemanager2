import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CompressTarCommand extends DelegatingFileCommand {
  CompressTarCommand(CommandAction action)
    : super(
        id: CommandId.compressTar,
        action: action,
        availability: CommandPredicates.canArchive,
      );
}
