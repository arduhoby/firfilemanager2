import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../file_operations/file_operations_state.dart';
import '../file_operations/panel_target_selection.dart';

class PanelTargetSelectorDialog extends StatefulWidget {
  const PanelTargetSelectorDialog({
    required this.catalog,
    required this.operation,
    this.allowMultiple = true,
    super.key,
  });

  final PanelTargetCatalog catalog;
  final PanelTargetOperation operation;
  final bool allowMultiple;

  @override
  State<PanelTargetSelectorDialog> createState() =>
      _PanelTargetSelectorDialogState();
}

class _PanelTargetSelectorDialogState extends State<PanelTargetSelectorDialog> {
  final Set<PanelId> _selectedPanelIds = {};

  String _operationLabel(gen.AppLocalizations l10n) {
    return switch (widget.operation) {
      PanelTargetOperation.copy => l10n.actionCopy,
      PanelTargetOperation.move => l10n.actionMove,
      PanelTargetOperation.sync => l10n.targetOperationSync,
      PanelTargetOperation.compress => l10n.actionCompress,
    };
  }

  void _toggleTarget(PanelTargetDescriptor target, bool selected) {
    if (!target.isSelectable) return;
    setState(() {
      if (!widget.allowMultiple) _selectedPanelIds.clear();
      if (selected) {
        _selectedPanelIds.add(target.panelId);
      } else {
        _selectedPanelIds.remove(target.panelId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final selectableCount = widget.catalog.selectableTargets.length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(_operationIcon(), color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${_operationLabel(l10n)} · ${l10n.targetPanels}'),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SourcePanelCard(source: widget.catalog.source),
            const SizedBox(height: 12),
            if (widget.allowMultiple)
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('target-select-all'),
                    onPressed: selectableCount == 0
                        ? null
                        : () => setState(() {
                            _selectedPanelIds
                              ..clear()
                              ..addAll(
                                widget.catalog.selectableTargets.map(
                                  (target) => target.panelId,
                                ),
                              );
                          }),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text(l10n.syncSelectAll),
                  ),
                  TextButton(
                    key: const ValueKey('target-clear-all'),
                    onPressed: _selectedPanelIds.isEmpty
                        ? null
                        : () => setState(_selectedPanelIds.clear),
                    child: Text(l10n.syncClearAll),
                  ),
                  const Spacer(),
                  Text(
                    l10n.targetSelectedSummary(
                      _selectedPanelIds.length,
                      selectableCount,
                    ),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.catalog.targets.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final target = widget.catalog.targets[index];
                  final reason = switch (target.blockReason) {
                    PanelTargetBlockReason.sameEndpoint =>
                      l10n.targetSameLocation,
                    PanelTargetBlockReason.connectionUnavailable =>
                      l10n.targetConnectionUnavailable,
                    PanelTargetBlockReason.unsupportedDestination =>
                      l10n.targetLocalPanelRequired,
                    null => null,
                  };
                  return CheckboxListTile(
                    key: ValueKey('target-panel-${target.panelId.value}'),
                    value: _selectedPanelIds.contains(target.panelId),
                    onChanged: target.isSelectable
                        ? (value) => _toggleTarget(target, value ?? false)
                        : null,
                    secondary: CircleAvatar(
                      radius: 17,
                      child: Text('${target.panelNumber}'),
                    ),
                    title: Text(l10n.panelNumber(target.panelNumber)),
                    subtitle: Text(
                      reason ??
                          '${target.providerDisplayName} · ${target.path}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: reason == null
                          ? null
                          : TextStyle(color: theme.colorScheme.error),
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton.icon(
          key: const ValueKey('target-confirm'),
          onPressed: _selectedPanelIds.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.catalog.targets
                      .where(
                        (target) => _selectedPanelIds.contains(target.panelId),
                      )
                      .map((target) => target.panelId)
                      .toList(growable: false),
                ),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(l10n.targetContinue),
        ),
      ],
    );
  }

  IconData _operationIcon() => switch (widget.operation) {
    PanelTargetOperation.copy => Icons.copy_outlined,
    PanelTargetOperation.move => Icons.drive_file_move_outline,
    PanelTargetOperation.sync => Icons.sync,
    PanelTargetOperation.compress => Icons.archive_outlined,
  };
}

class _SourcePanelCard extends StatelessWidget {
  const _SourcePanelCard({required this.source});

  final PanelTargetDescriptor source;

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
      child: ListTile(
        leading: Icon(Icons.output_rounded, color: theme.colorScheme.primary),
        title: Text(
          '${l10n.targetSourcePanel}: ${l10n.panelNumber(source.panelNumber)}',
        ),
        subtitle: Text(
          '${source.providerDisplayName} · ${source.path}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
