import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CompressTarGzCommand extends DelegatingFileCommand {
  CompressTarGzCommand(CommandAction action)
    : super(
        id: CommandId.compressTarGz,
        action: action,
        availability: CommandPredicates.canArchive,
      );
}
