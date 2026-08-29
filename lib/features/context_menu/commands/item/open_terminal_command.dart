import '../../../../core/commands/command_availability.dart';
import '../../../../core/commands/command_context.dart';
import '../../../../core/commands/command_id.dart';
import '../../../../core/commands/command_result.dart';
import '../../../../core/commands/file_command.dart';
import '../command_action.dart';

class OpenTerminalCommand implements FileCommand {
  const OpenTerminalCommand(this._action);

  final CommandAction _action;

  @override
  CommandId get id => CommandId.openTerminal;

  @override
  CommandAvailability evaluate(CommandContext context) {
    final hasLocalPath =
        context.supports(CommandCapability.localPath) ||
        context.supports(CommandCapability.mountedPath);
    if (!hasLocalPath || !context.supports(CommandCapability.terminal)) {
      return const CommandAvailability.hidden(
        'Terminal is available only for local or mounted paths.',
      );
    }
    return const CommandAvailability.available();
  }

  @override
  Future<CommandResult> execute(CommandContext context) => _action(context);
}
