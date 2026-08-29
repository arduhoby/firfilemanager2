import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  test('starts with two independent panels and panel A active', () {
    final workspace = container.read(panelWorkspaceProvider);

    expect(workspace.panelOrder, [PanelId.a, PanelId.b]);
    expect(workspace.panelCount, 2);
    expect(workspace.activePanelId, PanelId.a);
    expect(workspace.canAddPanel, isTrue);
    expect(workspace.canRemovePanel, isFalse);
    expect(workspace.destinationPanelIds, [PanelId.b]);
    expect(workspace.panel(PanelId.a).activeTab.currentPath, '/');
    expect(workspace.panel(PanelId.b).activeTab.currentPath, '/');
  });

  test('adds panels up to five with independent initial endpoints', () {
    final panels = container.read(panelWorkspaceProvider.notifier);

    final third = panels.addPanel(path: '/third');
    final fourth = panels.addPanel(path: '/fourth', providerId: 'sftp-1');
    final fifth = panels.addPanel(path: '/fifth');
    final workspace = container.read(panelWorkspaceProvider);

    expect(workspace.panelOrder, [PanelId.a, PanelId.b, third, fourth, fifth]);
    expect(workspace.panelCount, PanelWorkspaceState.maxPanelCount);
    expect(workspace.canAddPanel, isFalse);
    expect(workspace.activePanelId, fifth);
    expect(workspace.panel(third).activeTab.currentPath, '/third');
    expect(workspace.panel(fourth).activeTab.providerId, 'sftp-1');
    expect(() => panels.addPanel(path: '/sixth'), throwsA(isA<StateError>()));
  });

  test('updates selection, sorting, and navigation per panel only', () {
    final panels = container.read(panelWorkspaceProvider.notifier);
    final alpha = FileEntry(
      name: 'alpha.txt',
      path: '/a/alpha.txt',
      isDirectory: false,
      size: 10,
    );
    final beta = FileEntry(
      name: 'beta.txt',
      path: '/a/beta.txt',
      isDirectory: false,
      size: 20,
    );

    panels.setPath(PanelId.a, '/a');
    panels.setEntries(PanelId.a, [beta, alpha]);
    panels.toggleSelection(PanelId.a, beta.path);
    panels.toggleSort(PanelId.a, SortField.size);

    final workspace = container.read(panelWorkspaceProvider);
    expect(workspace.panel(PanelId.a).activeTab.currentPath, '/a');
    expect(workspace.panel(PanelId.a).activeTab.selectedEntries, [beta]);
    expect(
      workspace.panel(PanelId.a).activeTab.entries.map((entry) => entry.name),
      ['alpha.txt', 'beta.txt'],
    );
    expect(workspace.panel(PanelId.b).activeTab.currentPath, '/');
    expect(workspace.panel(PanelId.b).activeTab.entries, isEmpty);
    expect(workspace.panel(PanelId.b).activeTab.selectedPaths, isEmpty);
  });

  test('removes an active added panel and keeps at least two panels', () {
    final panels = container.read(panelWorkspaceProvider.notifier);
    final third = panels.addPanel(path: '/third');

    expect(panels.removePanel(third), isTrue);
    expect(container.read(panelWorkspaceProvider).activePanelId, PanelId.a);
    expect(
      container.read(panelStateProvider(third)).activeTab.currentPath,
      '/',
    );
    expect(panels.removePanel(PanelId.a), isFalse);
    expect(container.read(panelWorkspaceProvider).panelCount, 2);
  });

  test('reorders panels only when every panel appears exactly once', () {
    final panels = container.read(panelWorkspaceProvider.notifier);
    final third = panels.addPanel();

    panels.reorderPanels([third, PanelId.b, PanelId.a]);
    expect(container.read(panelWorkspaceProvider).panelOrder, [
      third,
      PanelId.b,
      PanelId.a,
    ]);
    expect(
      () => panels.reorderPanels([PanelId.a, PanelId.b, PanelId.b]),
      throwsArgumentError,
    );
  });

  test('clipboard keeps the dynamic source panel identity', () {
    final panels = container.read(panelWorkspaceProvider.notifier);
    final third = panels.addPanel(path: '/third');

    container
        .read(fileClipboardProvider.notifier)
        .copy(['/third/file.txt'], third, 'local');
    final clipboard = container.read(fileClipboardProvider);

    expect(clipboard?.sourcePanelId, third);
    expect(clipboard?.sourcePaths, ['/third/file.txt']);
    expect(clipboard?.operation, ClipboardOperation.copy);
  });

  test('restores and persists the workspace panel count', () async {
    SharedPreferences.setMockInitialValues({'workspace_panel_count': '4'});
    final panels = container.read(panelWorkspaceProvider.notifier);

    await panels.restorePanelCount();
    expect(container.read(panelWorkspaceProvider).panelCount, 4);
    expect(container.read(panelWorkspaceProvider).activePanelId, PanelId.a);

    panels.addPanel();
    await panels.persistPanelCount();

    final restoredContainer = ProviderContainer();
    addTearDown(restoredContainer.dispose);
    await restoredContainer
        .read(panelWorkspaceProvider.notifier)
        .restorePanelCount();

    expect(restoredContainer.read(panelWorkspaceProvider).panelCount, 5);
  });
}
