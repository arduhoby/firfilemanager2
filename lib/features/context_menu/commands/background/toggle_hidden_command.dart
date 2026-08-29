import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../../../../core/commands/command_result.dart';
import '../../../../core/commands/file_command.dart';
import '../command_action.dart';

class ToggleHiddenCommand implements FileCommand {
  const ToggleHiddenCommand(this._action);

  final CommandAction _action;

  @override
  CommandId get id => CommandId.toggleHidden;

  @override
  CommandAvailability evaluate(CommandContext context) =>
      const CommandAvailability.available();

  @override
  Future<CommandResult> execute(CommandContext context) => _action(context);
}
