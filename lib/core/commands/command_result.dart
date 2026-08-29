enum CommandResultState { completed, rejected, cancelled, failed }

class CommandResult {
  const CommandResult._({required this.state, this.message, this.error});

  const CommandResult.completed([String? message])
    : this._(state: CommandResultState.completed, message: message);

  const CommandResult.rejected(String message)
    : this._(state: CommandResultState.rejected, message: message);

  const CommandResult.cancelled([String? message])
    : this._(state: CommandResultState.cancelled, message: message);

  const CommandResult.failed(Object error)
    : this._(state: CommandResultState.failed, error: error);

  final CommandResultState state;
  final String? message;
  final Object? error;

  bool get succeeded => state == CommandResultState.completed;
}
