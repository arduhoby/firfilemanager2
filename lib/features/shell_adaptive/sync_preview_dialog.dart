import 'dart:math' as math;

import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../file_operations/sync_models.dart';

enum _SyncSortColumn {
  sourceName,
  sourceSize,
  sourceModified,
  status,
  destinationName,
  destinationSize,
  destinationModified,
}

class SyncPreviewDialog extends StatefulWidget {
  const SyncPreviewDialog({
    super.key,
    required this.sourcePath,
    required this.destPath,
    required this.items,
    this.onSave,
  });

  final String sourcePath;
  final String destPath;
  final List<SyncItem> items;
  final Future<void> Function(SyncPreviewSelection selection)? onSave;

  @override
  State<SyncPreviewDialog> createState() => _SyncPreviewDialogState();
}

class _SyncPreviewDialogState extends State<SyncPreviewDialog> {
  late final List<SyncItem> _items;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  _SyncSortColumn _sortColumn = _SyncSortColumn.sourceName;
  bool _sortAscending = true;
  SyncSelectionPolicy _policy = const SyncSelectionPolicy();
  String _query = '';
  bool _showSelectedOnly = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((item) => item.copyWith()).toList();
    _sortItems();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  int get _selectedCount => _items.where((item) => item.isSelected).length;

  bool? get _allSelectionState {
    if (_selectedCount == 0) return false;
    if (_selectedCount == _items.length) return true;
    return null;
  }

  List<SyncItem> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return _items.where((item) {
      if (_showSelectedOnly && !item.isSelected) return false;
      return query.isEmpty || item.relativePath.toLowerCase().contains(query);
    }).toList();
  }

  bool? _statusSelectionState(SyncStatus status) {
    final items = _items.where(
      (item) => item.status == status && item.canSelect,
    );
    if (items.isEmpty || items.every((item) => !item.isSelected)) return false;
    if (items.every((item) => item.isSelected)) return true;
    return null;
  }

  void _setStatusSelection(SyncStatus status, bool selected) {
    setState(() {
      _policy = switch (status) {
        SyncStatus.missing => _policy.copyWith(missing: selected),
        SyncStatus.modified => _policy.copyWith(modified: selected),
        SyncStatus.identical => _policy.copyWith(identical: selected),
        SyncStatus.inaccessible => _policy,
      };
      for (final item in _items) {
        if (item.status == status && item.canSelect) {
          item.isSelected = selected;
        }
      }
    });
  }

  SyncPreviewSelection _selectionSnapshot() {
    final included = <String>{};
    final excluded = <String>{};
    for (final item in _items) {
      final policySelected = _policy.selects(item.status);
      if (item.isSelected && !policySelected) included.add(item.relativePath);
      if (!item.isSelected && policySelected) excluded.add(item.relativePath);
    }
    return SyncPreviewSelection(
      selectedItems: _items.where((item) => item.isSelected).toList(),
      policy: _policy,
      includedPaths: included,
      excludedPaths: excluded,
    );
  }

  void _setAll(bool selected) {
    setState(() {
      _policy = SyncSelectionPolicy(
        missing: selected,
        modified: selected,
        identical: selected,
      );
      for (final item in _items) {
        item.isSelected = selected && item.canSelect;
      }
    });
  }

  void _selectChanges() {
    setState(() {
      _policy = const SyncSelectionPolicy();
      for (final item in _items) {
        item.isSelected =
            item.status == SyncStatus.missing ||
            item.status == SyncStatus.modified;
      }
    });
  }

  void _toggleItem(SyncItem item, bool selected) {
    setState(() => item.isSelected = selected);
  }

  void _setSort(_SyncSortColumn column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
      _sortItems();
    });
  }

  void _sortItems() {
    _items.sort((left, right) {
      final result = _compareValues(
        _sortValue(left, _sortColumn),
        _sortValue(right, _sortColumn),
      );
      if (result != 0) return _sortAscending ? result : -result;
      return left.relativePath.toLowerCase().compareTo(
        right.relativePath.toLowerCase(),
      );
    });
  }

  Object? _sortValue(SyncItem item, _SyncSortColumn column) => switch (column) {
    _SyncSortColumn.sourceName => item.relativePath.toLowerCase(),
    _SyncSortColumn.sourceSize => item.sourceEntry.size,
    _SyncSortColumn.sourceModified => item.sourceEntry.modified,
    _SyncSortColumn.status => item.status.index,
    _SyncSortColumn.destinationName =>
      item.destinationEntry == null ? null : item.relativePath.toLowerCase(),
    _SyncSortColumn.destinationSize => item.destinationEntry?.size,
    _SyncSortColumn.destinationModified => item.destinationEntry?.modified,
  };

  int _compareValues(Object? left, Object? right) {
    if (identical(left, right)) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    if (left is num && right is num) return left.compareTo(right);
    if (left is DateTime && right is DateTime) return left.compareTo(right);
    return left.toString().compareTo(right.toString());
  }

  int _dataColumnIndex(_SyncSortColumn column) => switch (column) {
    _SyncSortColumn.sourceName => 1,
    _SyncSortColumn.sourceSize => 2,
    _SyncSortColumn.sourceModified => 3,
    _SyncSortColumn.status => 4,
    _SyncSortColumn.destinationName => 5,
    _SyncSortColumn.destinationSize => 6,
    _SyncSortColumn.destinationModified => 7,
  };

  String _formatDate(BuildContext context, DateTime? value) {
    if (value == null) return '—';
    return DateFormat.yMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm().format(value.toLocal());
  }

  Color _statusColor(BuildContext context, SyncStatus status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (status) {
      SyncStatus.missing => dark ? Colors.red.shade300 : Colors.red.shade700,
      SyncStatus.modified => dark ? Colors.blue.shade300 : Colors.blue.shade700,
      SyncStatus.identical =>
        dark ? Colors.green.shade300 : Colors.green.shade700,
      SyncStatus.inaccessible =>
        dark ? Colors.orange.shade300 : Colors.orange.shade800,
    };
  }

  IconData _statusIcon(SyncStatus status) => switch (status) {
    SyncStatus.missing => Icons.add_circle_outline,
    SyncStatus.modified => Icons.change_circle_outlined,
    SyncStatus.identical => Icons.check_circle_outline,
    SyncStatus.inaccessible => Icons.warning_amber_rounded,
  };

  String _statusLabel(gen.AppLocalizations l10n, SyncStatus status) =>
      switch (status) {
        SyncStatus.missing => l10n.syncStatusNew,
        SyncStatus.modified => l10n.syncStatusDifferent,
        SyncStatus.identical => l10n.syncStatusEqual,
        SyncStatus.inaccessible => l10n.syncStatusInaccessible,
      };

  DataColumn _sortableColumn({
    required Widget label,
    required _SyncSortColumn column,
    bool numeric = false,
  }) => DataColumn(
    label: label,
    numeric: numeric,
    onSort: (_, ascending) => _setSort(column, ascending),
  );

  Widget _panelHeader({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String path,
    required bool source,
  }) {
    final theme = Theme.of(context);
    final color = source
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCell(
    BuildContext context,
    SyncItem item, {
    required bool destination,
  }) {
    final color = _statusColor(context, item.status);
    final entry = destination ? item.destinationEntry : item.sourceEntry;
    final label = entry == null ? null : item.relativePath;
    final tooltip = [
      label ?? gen.AppLocalizations.of(context)!.syncMissingDestination,
      if (item.error != null) item.error!,
    ].join('\n');
    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Row(
          children: [
            Icon(
              entry == null
                  ? Icons.remove_circle_outline
                  : entry.isDirectory
                  ? Icons.folder
                  : Icons.insert_drive_file,
              color: color,
              size: 18,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label ??
                    gen.AppLocalizations.of(context)!.syncMissingDestination,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontStyle: entry == null ? FontStyle.italic : null,
                  fontWeight: item.status == SyncStatus.identical
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coloredValue(BuildContext context, SyncItem item, String value) =>
      Text(value, style: TextStyle(color: _statusColor(context, item.status)));

  Widget _buildTable(BuildContext context, gen.AppLocalizations l10n) {
    final theme = Theme.of(context);
    final rows = _visibleItems.map((item) {
      final destination = item.destinationEntry;
      final statusColor = _statusColor(context, item.status);
      return DataRow(
        selected: item.isSelected,
        onSelectChanged: item.canSelect
            ? (selected) => _toggleItem(item, selected ?? false)
            : null,
        color: WidgetStateProperty.resolveWith((states) {
          final alpha = states.contains(WidgetState.selected) ? 0.20 : 0.085;
          return statusColor.withValues(alpha: alpha);
        }),
        cells: [
          DataCell(
            Checkbox(
              key: ValueKey('sync-select-${item.relativePath}'),
              value: item.isSelected,
              activeColor: statusColor,
              onChanged: item.canSelect
                  ? (value) => _toggleItem(item, value ?? false)
                  : null,
            ),
          ),
          DataCell(_fileCell(context, item, destination: false)),
          DataCell(
            _coloredValue(context, item, filesize(item.sourceEntry.size)),
          ),
          DataCell(
            _coloredValue(
              context,
              item,
              _formatDate(context, item.sourceEntry.modified),
            ),
          ),
          DataCell(
            Tooltip(
              message: item.error ?? item.comparisonReason ?? '',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_statusIcon(item.status), color: statusColor, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel(l10n, item.status),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          DataCell(_fileCell(context, item, destination: true)),
          DataCell(
            _coloredValue(
              context,
              item,
              destination == null ? '—' : filesize(destination.size),
            ),
          ),
          DataCell(
            _coloredValue(
              context,
              item,
              _formatDate(context, destination?.modified),
            ),
          ),
        ],
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _verticalController,
          child: Scrollbar(
            controller: _horizontalController,
            notificationPredicate: (notification) => notification.depth == 1,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.max(1080, constraints.maxWidth),
                ),
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: _dataColumnIndex(_sortColumn),
                  sortAscending: _sortAscending,
                  headingRowColor: WidgetStatePropertyAll(
                    theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.65,
                    ),
                  ),
                  columns: [
                    DataColumn(
                      label: Checkbox(
                        key: const ValueKey('sync-select-all'),
                        tristate: true,
                        value: _allSelectionState,
                        onChanged: (value) =>
                            _setAll(value ?? _selectedCount != _items.length),
                      ),
                    ),
                    _sortableColumn(
                      label: Text(
                        '${l10n.syncSourcePanel} · ${l10n.syncColumnFile}',
                      ),
                      column: _SyncSortColumn.sourceName,
                    ),
                    _sortableColumn(
                      label: Text(l10n.syncColumnSize),
                      column: _SyncSortColumn.sourceSize,
                      numeric: true,
                    ),
                    _sortableColumn(
                      label: Text(l10n.syncColumnModified),
                      column: _SyncSortColumn.sourceModified,
                    ),
                    _sortableColumn(
                      label: Text(l10n.syncColumnStatus),
                      column: _SyncSortColumn.status,
                    ),
                    _sortableColumn(
                      label: Text(
                        '${l10n.syncDestinationPanel} · ${l10n.syncColumnFile}',
                      ),
                      column: _SyncSortColumn.destinationName,
                    ),
                    _sortableColumn(
                      label: Text(l10n.syncColumnSize),
                      column: _SyncSortColumn.destinationSize,
                      numeric: true,
                    ),
                    _sortableColumn(
                      label: Text(l10n.syncColumnModified),
                      column: _SyncSortColumn.destinationModified,
                    ),
                  ],
                  rows: rows,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusToggle(
    BuildContext context,
    gen.AppLocalizations l10n,
    SyncStatus status,
  ) {
    final color = _statusColor(context, status);
    final count = _items.where((item) => item.status == status).length;
    return Container(
      padding: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: ValueKey('sync-select-status-${status.name}'),
            tristate: true,
            value: _statusSelectionState(status),
            activeColor: color,
            onChanged: status == SyncStatus.inaccessible
                ? null
                : (value) => _setStatusSelection(
                    status,
                    value ?? _statusSelectionState(status) != true,
                  ),
          ),
          Icon(_statusIcon(status), color: color, size: 17),
          const SizedBox(width: 5),
          Text(
            '${_statusLabel(l10n, status)} ($count)',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeaders(BuildContext context, gen.AppLocalizations l10n) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final source = _panelHeader(
            context: context,
            icon: Icons.folder_copy_outlined,
            title: l10n.syncSourcePanel,
            path: widget.sourcePath,
            source: true,
          );
          final destination = _panelHeader(
            context: context,
            icon: Icons.folder_outlined,
            title: l10n.syncDestinationPanel,
            path: widget.destPath,
            source: false,
          );
          if (constraints.maxWidth < 650) {
            return Column(
              children: [
                Row(children: [source]),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Icon(Icons.arrow_downward_rounded, size: 20),
                ),
                Row(children: [destination]),
              ],
            );
          }
          return Row(
            children: [
              source,
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded),
              ),
              destination,
            ],
          );
        },
      );

  Widget _buildCards(BuildContext context, gen.AppLocalizations l10n) {
    return ListView.separated(
      controller: _verticalController,
      padding: const EdgeInsets.all(8),
      itemCount: _visibleItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _visibleItems[index];
        final color = _statusColor(context, item.status);
        final destination = item.destinationEntry;
        return Material(
          color: color.withValues(alpha: item.isSelected ? 0.18 : 0.08),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: color.withValues(alpha: 0.40)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: item.canSelect
                ? () => _toggleItem(item, !item.isSelected)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        key: ValueKey('sync-card-select-${item.relativePath}'),
                        value: item.isSelected,
                        activeColor: color,
                        onChanged: item.canSelect
                            ? (value) => _toggleItem(item, value ?? false)
                            : null,
                      ),
                      Icon(_statusIcon(item.status), color: color),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _statusLabel(l10n, item.status),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.comparisonReason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.comparisonReason!,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(l10n.syncSourcePanel),
                  const SizedBox(height: 4),
                  _fileCell(context, item, destination: false),
                  Padding(
                    padding: const EdgeInsets.only(left: 25, top: 3),
                    child: _coloredValue(
                      context,
                      item,
                      '${filesize(item.sourceEntry.size)} · '
                      '${_formatDate(context, item.sourceEntry.modified)}',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 5),
                    child: Icon(Icons.arrow_downward_rounded, size: 18),
                  ),
                  Text(l10n.syncDestinationPanel),
                  const SizedBox(height: 4),
                  _fileCell(context, item, destination: true),
                  Padding(
                    padding: const EdgeInsets.only(left: 25, top: 3),
                    child: _coloredValue(
                      context,
                      item,
                      destination == null
                          ? '—'
                          : '${filesize(destination.size)} · '
                                '${_formatDate(context, destination.modified)}',
                    ),
                  ),
                  if (item.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.error!,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildComparison(BuildContext context, gen.AppLocalizations l10n) =>
      LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 720
            ? _buildCards(context, l10n)
            : _buildTable(context, l10n),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      title: Row(
        children: [
          Icon(Icons.compare_arrows, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.syncPreviewTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.92,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPanelHeaders(context, l10n),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _statusToggle(context, l10n, SyncStatus.missing),
                _statusToggle(context, l10n, SyncStatus.modified),
                _statusToggle(context, l10n, SyncStatus.identical),
                if (_items.any(
                  (item) => item.status == SyncStatus.inaccessible,
                ))
                  _statusToggle(context, l10n, SyncStatus.inaccessible),
                Container(
                  padding: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('sync-select-all-toolbar'),
                        tristate: true,
                        value: _allSelectionState,
                        onChanged: (value) =>
                            _setAll(value ?? _selectedCount != _items.length),
                      ),
                      Text(
                        '${l10n.syncSelectAll} (${_items.where((item) => item.canSelect).length})',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.syncSelectedSummary(_selectedCount, _items.length),
                  style: theme.textTheme.labelLarge,
                ),
                OutlinedButton.icon(
                  onPressed: _selectChanges,
                  icon: const Icon(Icons.difference_outlined, size: 18),
                  label: Text(l10n.syncSelectChanges),
                ),
                OutlinedButton.icon(
                  onPressed: () => _setAll(false),
                  icon: const Icon(Icons.deselect, size: 18),
                  label: Text(l10n.syncClearAll),
                ),
                FilterChip(
                  selected: _showSelectedOnly,
                  onSelected: (value) =>
                      setState(() => _showSelectedOnly = value),
                  avatar: const Icon(Icons.checklist, size: 17),
                  label: Text(l10n.syncShowSelectedOnly),
                ),
                SizedBox(
                  width: 230,
                  child: TextField(
                    key: const ValueKey('sync-search'),
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 19),
                      hintText: l10n.syncSearchHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _buildComparison(context, l10n),
                ),
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
        if (widget.onSave != null)
          OutlinedButton.icon(
            onPressed: _selectedCount == 0
                ? null
                : () async => widget.onSave!(_selectionSnapshot()),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(l10n.syncSaveJob),
          ),
        FilledButton.icon(
          onPressed: _selectedCount == 0
              ? null
              : () => Navigator.pop(
                  context,
                  _items.where((item) => item.isSelected).toList(),
                ),
          icon: const Icon(Icons.sync, size: 18),
          label: Text(l10n.syncStartSelected(_selectedCount)),
        ),
      ],
    );
  }
}
