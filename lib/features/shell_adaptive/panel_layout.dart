import 'package:flutter/foundation.dart';

import '../file_operations/file_operations_state.dart';

/// Canonical row layout for a workspace containing two to five panels.
@immutable
class PanelLayoutSpec {
  const PanelLayoutSpec._(this.rows);

  factory PanelLayoutSpec.forPanels(List<PanelId> panelOrder) {
    assert(
      panelOrder.length >= PanelWorkspaceState.minPanelCount &&
          panelOrder.length <= PanelWorkspaceState.maxPanelCount,
    );

    return switch (panelOrder.length) {
      2 || 3 => PanelLayoutSpec._([List.unmodifiable(panelOrder)]),
      4 => PanelLayoutSpec._([
        List.unmodifiable(panelOrder.take(2)),
        List.unmodifiable(panelOrder.skip(2)),
      ]),
      5 => PanelLayoutSpec._([
        List.unmodifiable(panelOrder.take(3)),
        List.unmodifiable(panelOrder.skip(3)),
      ]),
      _ => throw ArgumentError.value(
        panelOrder.length,
        'panelOrder.length',
        'Only two to five panels are supported.',
      ),
    };
  }

  final List<List<PanelId>> rows;
}
