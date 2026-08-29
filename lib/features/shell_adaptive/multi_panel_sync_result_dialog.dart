import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../file_operations/file_operations_state.dart';
import '../file_operations/multi_panel_sync_coordinator.dart';

class MultiPanelSyncResultDialog extends StatelessWidget {
  const MultiPanelSyncResultDialog({
    required this.result,
    required this.panelNumbers,
    super.key,
  });

  final MultiPanelSyncResult result;
  final Map<PanelId, int> panelNumbers;

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.multiSyncResultTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.multiSyncSummary(
                result.successfulTargetCount,
                result.targets.length,
              ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: result.targets.length,
                itemBuilder: (context, index) {
                  final target = result.targets[index];
                  final execution = target.execution;
                  final (icon, color, status) = switch (target.state) {
                    PanelSyncTargetState.completed => (
                      Icons.check_circle_outline,
                      Colors.green,
                      execution == null
                          ? l10n.multiSyncCompleted
                          : l10n.syncResultSummary(
                              execution.updatedFiles,
                              execution.createdFiles,
                            ),
                    ),
                    PanelSyncTargetState.noChanges => (
                      Icons.done_all,
                      Colors.green,
                      l10n.multiSyncNoChanges,
                    ),
                    PanelSyncTargetState.failed => (
                      Icons.error_outline,
                      theme.colorScheme.error,
                      target.error ?? l10n.multiSyncFailed,
                    ),
                    PanelSyncTargetState.cancelled => (
                      Icons.cancel_outlined,
                      theme.colorScheme.error,
                      l10n.multiSyncCancelled,
                    ),
                    PanelSyncTargetState.skipped => (
                      Icons.skip_next_outlined,
                      theme.colorScheme.onSurfaceVariant,
                      l10n.multiSyncSkipped,
                    ),
                  };
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(
                      l10n.panelNumber(panelNumbers[target.panelId] ?? 0),
                    ),
                    subtitle: Text(status),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionClose),
        ),
      ],
    );
  }
}
