import '../../../../core/commands/command_id.dart';
import '../command_action.dart';
import '../command_predicates.dart';

class MergeFilePartsCommand extends DelegatingFileCommand {
  MergeFilePartsCommand(CommandAction action)
    : super(
        id: CommandId.mergeFileParts,
        action: action,
        availability: CommandPredicates.canMergeFileParts,
      );
}
