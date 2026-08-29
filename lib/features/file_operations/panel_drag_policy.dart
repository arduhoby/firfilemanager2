import 'file_operations_state.dart';

/// Keeps drag-and-drop as one source panel to one explicit target panel.
class PanelDragPolicy {
  const PanelDragPolicy._();

  static PanelId? resolveTarget({
    required PanelId sourcePanelId,
    required PanelId targetPanelId,
    required int entryCount,
  }) {
    if (entryCount <= 0 || sourcePanelId == targetPanelId) return null;
    return targetPanelId;
  }
}
