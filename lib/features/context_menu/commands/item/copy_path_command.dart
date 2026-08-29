import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../../../../core/commands/command_result.dart';
import '../../../../core/commands/file_command.dart';
import '../command_action.dart';

class CopyPathCommand implements FileCommand {
  const CopyPathCommand(this._action);

  final CommandAction _action;

  @override
  CommandId get id => CommandId.copyPath;

  @override
  CommandAvailability evaluate(CommandContext context) =>
      context.clickedEntry == null && context.currentPath.isEmpty
      ? const CommandAvailability.disabled('There is no path to copy.')
      : const CommandAvailability.available();

  @override
  Future<CommandResult> execute(CommandContext context) => _action(context);
}
