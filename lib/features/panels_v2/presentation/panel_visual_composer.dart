import 'panel_presentation_model.dart';

class PanelVisualInput {
  const PanelVisualInput({
    required this.panelId,
    required this.title,
    required this.currentPath,
    required this.isActive,
    required this.isLoading,
    required this.entryCount,
    required this.selectedCount,
    required this.showHidden,
  });

  final String panelId;
  final String title;
  final String currentPath;
  final bool isActive;
  final bool isLoading;
  final int entryCount;
  final int selectedCount;
  final bool showHidden;
}

class PanelVisualComposer {
  const PanelVisualComposer();

  PanelPresentationModel compose(PanelVisualInput input) =>
      PanelPresentationModel(
        panelId: input.panelId,
        title: input.title,
        currentPath: input.currentPath,
        isActive: input.isActive,
        isLoading: input.isLoading,
        entryCount: input.entryCount,
        selectedCount: input.selectedCount,
        showHidden: input.showHidden,
      );
}
