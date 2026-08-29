import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/panel_target_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PanelTargetSelectionPolicy', () {
    test('does not show a selector when there are exactly two panels', () {
      expect(PanelTargetSelectionPolicy.shouldShowSelector(2), isFalse);
    });

    test('shows a selector when there are three to five panels', () {
      for (var panelCount = 3; panelCount <= 5; panelCount++) {
        expect(
          PanelTargetSelectionPolicy.shouldShowSelector(panelCount),
          isTrue,
          reason: '$panelCount panels provide multiple target choices',
        );
      }
    });
  });

  test('builds selectable targets and blocks invalid panel endpoints', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final panels = container.read(panelWorkspaceProvider.notifier);

    panels.setProviderAndPath(PanelId.a, 'local', '/source');
    panels.setProviderAndPath(PanelId.b, 'local', '/destination');
    final sameEndpoint = panels.addPanel(path: '/source/');
    final disconnected = panels.addPanel(
      path: '/remote',
      providerId: 'sftp-offline',
    );
    final connectedRemote = panels.addPanel(
      path: '/remote-backup',
      providerId: 'sftp-online',
    );

    final catalog = PanelTargetCatalog.fromWorkspace(
      workspace: container.read(panelWorkspaceProvider),
      sourcePanelId: PanelId.a,
      providerStatus: (providerId) => PanelProviderStatus(
        displayName: providerId,
        isAvailable: providerId != 'sftp-offline',
      ),
    );

    expect(catalog.source.panelId, PanelId.a);
    expect(catalog.selectableTargets.map((target) => target.panelId), [
      PanelId.b,
      connectedRemote,
    ]);
    expect(
      catalog.targets
          .singleWhere((target) => target.panelId == sameEndpoint)
          .blockReason,
      PanelTargetBlockReason.sameEndpoint,
    );
    expect(
      catalog.targets
          .singleWhere((target) => target.panelId == disconnected)
          .blockReason,
      PanelTargetBlockReason.connectionUnavailable,
    );

    final localOnlyCatalog = PanelTargetCatalog.fromWorkspace(
      workspace: container.read(panelWorkspaceProvider),
      sourcePanelId: PanelId.a,
      providerStatus: (providerId) => PanelProviderStatus(
        displayName: providerId,
        isAvailable: providerId != 'sftp-offline',
      ),
      targetSupported: (targetState) => targetState.providerId == 'local',
    );
    expect(
      localOnlyCatalog.targets
          .singleWhere((target) => target.panelId == connectedRemote)
          .blockReason,
      PanelTargetBlockReason.unsupportedDestination,
    );

    final archiveCatalog = PanelTargetCatalog.fromWorkspace(
      workspace: container.read(panelWorkspaceProvider),
      sourcePanelId: PanelId.a,
      providerStatus: (providerId) => PanelProviderStatus(
        displayName: providerId,
        isAvailable: providerId != 'sftp-offline',
      ),
      targetSupported: (targetState) => targetState.providerId == 'local',
      allowSameEndpoint: true,
    );
    expect(
      archiveCatalog.targets
          .singleWhere((target) => target.panelId == sameEndpoint)
          .isSelectable,
      isTrue,
    );
  });
}
