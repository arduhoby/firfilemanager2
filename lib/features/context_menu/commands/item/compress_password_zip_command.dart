import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class CompressPasswordZipCommand extends DelegatingFileCommand {
  CompressPasswordZipCommand(CommandAction action)
    : super(
        id: CommandId.compressPasswordZip,
        action: action,
        availability: CommandPredicates.canArchive,
      );
}
