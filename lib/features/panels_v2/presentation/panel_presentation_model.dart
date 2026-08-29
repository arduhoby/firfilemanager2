class PanelPresentationModel {
  const PanelPresentationModel({
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
