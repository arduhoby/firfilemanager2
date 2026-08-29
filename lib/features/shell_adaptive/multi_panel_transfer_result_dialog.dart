import 'package:flutter/material.dart';

import '../../core/storage/models/transfer_progress.dart';
import '../../l10n/generated/app_localizations.dart' as gen;
import '../file_operations/file_operations_state.dart';
import '../file_operations/multi_panel_transfer_coordinator.dart';

class MultiPanelTransferResultDialog extends StatelessWidget {
  const MultiPanelTransferResultDialog({
    required this.result,
    required this.panelNumbers,
    super.key,
  });

  final MultiPanelTransferResult result;
  final Map<PanelId, int> panelNumbers;

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        result.operation == TransferOperation.zip
            ? l10n.multiArchiveResultTitle
            : l10n.multiTransferResultTitle,
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.multiTransferPartial(
                result.successfulTargetCount,
                result.targets.length,
              ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: result.targets.length,
                itemBuilder: (context, index) {
                  final target = result.targets[index];
                  final (icon, color, status) = switch (target.state) {
                    PanelTransferTargetState.completed => (
                      Icons.check_circle_outline,
                      Colors.green,
                      l10n.multiTransferCompleted,
                    ),
                    PanelTransferTargetState.failed => (
                      Icons.error_outline,
                      theme.colorScheme.error,
                      l10n.multiTransferFailed,
                    ),
                    PanelTransferTargetState.cancelled => (
                      Icons.cancel_outlined,
                      theme.colorScheme.error,
                      l10n.multiTransferCancelled,
                    ),
                    PanelTransferTargetState.skipped => (
                      Icons.skip_next_outlined,
                      theme.colorScheme.onSurfaceVariant,
                      l10n.multiTransferSkipped,
                    ),
                  };
                  return ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(
                      l10n.panelNumber(panelNumbers[target.panelId] ?? 0),
                    ),
                    subtitle: Text(target.error ?? status),
                  );
                },
              ),
            ),
            if (result.operation == TransferOperation.move &&
                !result.sourceDeleted) ...[
              const SizedBox(height: 10),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10n.multiTransferSourcePreserved),
                ),
              ),
            ],
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
