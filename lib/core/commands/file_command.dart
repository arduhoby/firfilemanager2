import 'command_availability.dart';
import 'command_context.dart';
import 'command_id.dart';
import 'command_result.dart';

abstract interface class FileCommand {
  CommandId get id;

  CommandAvailability evaluate(CommandContext context);

  Future<CommandResult> execute(CommandContext context);
}
