import 'package:fir_file_manager/core/commands/command_availability.dart';
import 'package:fir_file_manager/core/commands/command_context.dart';
import 'package:fir_file_manager/core/commands/command_id.dart';
import 'package:fir_file_manager/core/commands/command_registry.dart';
import 'package:fir_file_manager/core/commands/command_result.dart';
import 'package:fir_file_manager/core/commands/file_command.dart';
import 'package:fir_file_manager/features/context_menu/application/command_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const context = CommandContext(
    sourcePanelId: 'panel-a',
    providerId: 'local',
    currentPath: 'C:\\',
  );

  test('registry rejects duplicate command owners', () {
    expect(
      () => CommandRegistry(<FileCommand>[
        const _FakeCommand(CommandId.refresh),
        const _FakeCommand(CommandId.refresh),
      ]),
      throwsArgumentError,
    );
  });

  test(
    'orchestrator rejects disabled commands without executing them',
    () async {
      var executed = false;
      final command = _FakeCommand(
        CommandId.delete,
        availability: const CommandAvailability.disabled('blocked'),
        action: (_) async {
          executed = true;
          return const CommandResult.completed();
        },
      );
      final orchestrator = CommandOrchestrator(
        registry: CommandRegistry(<FileCommand>[command]),
      );

      final result = await orchestrator.dispatch(CommandId.delete, context);

      expect(result.state, CommandResultState.rejected);
      expect(executed, isFalse);
    },
  );

  test('orchestrator reports the final result exactly once', () async {
    var reports = 0;
    final orchestrator = CommandOrchestrator(
      registry: CommandRegistry(<FileCommand>[
        const _FakeCommand(CommandId.refresh),
      ]),
      report: (id, context, result) async => reports++,
    );

    final result = await orchestrator.dispatch(CommandId.refresh, context);

    expect(result.succeeded, isTrue);
    expect(reports, 1);
  });
}

class _FakeCommand implements FileCommand {
  const _FakeCommand(
    this.id, {
    this.availability = const CommandAvailability.available(),
    this.action,
  });

  @override
  final CommandId id;
  final CommandAvailability availability;
  final Future<CommandResult> Function(CommandContext context)? action;

  @override
  CommandAvailability evaluate(CommandContext context) => availability;

  @override
  Future<CommandResult> execute(CommandContext context) =>
      action?.call(context) ??
      Future<CommandResult>.value(const CommandResult.completed());
}
