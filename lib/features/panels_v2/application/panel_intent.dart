import '../../../core/commands/command_id.dart';

sealed class PanelIntent {
  const PanelIntent(this.panelId);

  final String panelId;
}

class NavigatePanelIntent extends PanelIntent {
  const NavigatePanelIntent(super.panelId, this.path);

  final String path;
}

class InvokePanelCommandIntent extends PanelIntent {
  const InvokePanelCommandIntent(super.panelId, this.commandId);

  final CommandId commandId;
}

class BeginPanelDragIntent extends PanelIntent {
  const BeginPanelDragIntent(super.panelId, this.entryPaths);

  final List<String> entryPaths;
}
