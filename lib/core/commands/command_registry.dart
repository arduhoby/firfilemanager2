import 'command_id.dart';
import 'file_command.dart';

class CommandRegistry {
  CommandRegistry(Iterable<FileCommand> commands)
    : _commands = <CommandId, FileCommand>{
        for (final command in commands) command.id: command,
      } {
    if (_commands.length != commands.length) {
      throw ArgumentError('Every command id must have exactly one owner.');
    }
  }

  final Map<CommandId, FileCommand> _commands;

  FileCommand resolve(CommandId id) {
    final command = _commands[id];
    if (command == null) {
      throw StateError('No command registered for $id.');
    }
    return command;
  }

  Iterable<FileCommand> get commands => _commands.values;
}
