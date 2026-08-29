import 'package:flutter/foundation.dart';

import 'file_operations_state.dart';

enum PanelTargetOperation { copy, move, sync, compress }

abstract final class PanelTargetSelectionPolicy {
  static bool shouldShowSelector(int panelCount) =>
      panelCount > PanelWorkspaceState.minPanelCount;
}

enum PanelTargetBlockReason {
  sameEndpoint,
  connectionUnavailable,
  unsupportedDestination,
}

@immutable
class PanelProviderStatus {
  const PanelProviderStatus({
    required this.displayName,
    required this.isAvailable,
  });

  final String displayName;
  final bool isAvailable;
}

@immutable
class PanelTargetDescriptor {
  const PanelTargetDescriptor({
    required this.panelId,
    required this.panelNumber,
    required this.providerId,
    required this.providerDisplayName,
    required this.path,
    this.blockReason,
  });

  final PanelId panelId;
  final int panelNumber;
  final String providerId;
  final String providerDisplayName;
  final String path;
  final PanelTargetBlockReason? blockReason;

  bool get isSelectable => blockReason == null;
}

@immutable
class PanelTargetCatalog {
  const PanelTargetCatalog({required this.source, required this.targets});

  factory PanelTargetCatalog.fromWorkspace({
    required PanelWorkspaceState workspace,
    required PanelId sourcePanelId,
    required PanelProviderStatus Function(String providerId) providerStatus,
    bool Function(TabState targetState)? targetSupported,
    bool allowSameEndpoint = false,
  }) {
    final sourceState = workspace.panel(sourcePanelId).activeTab;
    final sourceProviderStatus = providerStatus(sourceState.providerId);
    final source = PanelTargetDescriptor(
      panelId: sourcePanelId,
      panelNumber: workspace.panelOrder.indexOf(sourcePanelId) + 1,
      providerId: sourceState.providerId,
      providerDisplayName: sourceProviderStatus.displayName,
      path: sourceState.currentPath,
    );

    final targets = workspace.panelOrder
        .where((panelId) => panelId != sourcePanelId)
        .map((panelId) {
          final targetState = workspace.panel(panelId).activeTab;
          final targetProviderStatus = providerStatus(targetState.providerId);
          final isSameEndpoint =
              targetState.providerId == sourceState.providerId &&
              _normalizedPath(targetState.currentPath) ==
                  _normalizedPath(sourceState.currentPath);
          final blockReason = !targetProviderStatus.isAvailable
              ? PanelTargetBlockReason.connectionUnavailable
              : targetSupported != null && !targetSupported(targetState)
              ? PanelTargetBlockReason.unsupportedDestination
              : isSameEndpoint && !allowSameEndpoint
              ? PanelTargetBlockReason.sameEndpoint
              : null;

          return PanelTargetDescriptor(
            panelId: panelId,
            panelNumber: workspace.panelOrder.indexOf(panelId) + 1,
            providerId: targetState.providerId,
            providerDisplayName: targetProviderStatus.displayName,
            path: targetState.currentPath,
            blockReason: blockReason,
          );
        })
        .toList(growable: false);

    return PanelTargetCatalog(source: source, targets: targets);
  }

  final PanelTargetDescriptor source;
  final List<PanelTargetDescriptor> targets;

  List<PanelTargetDescriptor> get selectableTargets =>
      targets.where((target) => target.isSelectable).toList(growable: false);

  static String _normalizedPath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
