import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CompressZipCommand extends DelegatingFileCommand {
  CompressZipCommand(CommandAction action)
    : super(
        id: CommandId.compressZip,
        action: action,
        availability: CommandPredicates.canArchive,
      );
}
