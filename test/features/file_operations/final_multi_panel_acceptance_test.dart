import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/multi_panel_sync_coordinator.dart';
import 'package:fir_file_manager/features/file_operations/multi_panel_transfer_coordinator.dart';
import 'package:fir_file_manager/features/file_operations/panel_drag_policy.dart';
import 'package:fir_file_manager/features/file_operations/panel_target_selection.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:fir_file_manager/features/shell_adaptive/panel_layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'five-panel workspace keeps multi operations and drag contracts',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panels = container.read(panelWorkspaceProvider.notifier);
      panels.setPath(PanelId.a, '/source');
      panels.setPath(PanelId.b, '/backup-2');
      final third = panels.addPanel(path: '/backup-3');
      final fourth = panels.addPanel(path: '/backup-4');
      final fifth = panels.addPanel(path: '/backup-5');
      final workspace = container.read(panelWorkspaceProvider);

      expect(PanelLayoutSpec.forPanels(workspace.panelOrder).rows, [
        [PanelId.a, PanelId.b, third],
        [fourth, fifth],
      ]);

      final catalog = PanelTargetCatalog.fromWorkspace(
        workspace: workspace,
        sourcePanelId: PanelId.a,
        providerStatus: (_) =>
            const PanelProviderStatus(displayName: 'Local', isAvailable: true),
      );
      final targetIds = catalog.selectableTargets
          .map((target) => target.panelId)
          .toList();
      expect(targetIds, [PanelId.b, third, fourth, fifth]);

      final transferFinals = <TransferProgress>[];
      final transfer = await const MultiPanelTransferCoordinator().execute(
        operation: TransferOperation.copy,
        targetPanelIds: targetIds,
      transferTarget: (_) async => TransferProgress(
          operation: TransferOperation.copy,
          state: TransferState.completed,
        ),
        publishFinalProgress: transferFinals.add,
      );
      expect(transfer.successfulTargetCount, 4);
      expect(transferFinals, hasLength(1));

      SyncItem syncItem(PanelId panelId) => SyncItem(
        sourceEntry: FileEntry(
          name: '${panelId.value}.txt',
          path: '/source/${panelId.value}.txt',
          isDirectory: false,
          size: 1,
        ),
        relativePath: '${panelId.value}.txt',
        depth: 0,
        status: SyncStatus.missing,
        isSelected: true,
      );

      final syncFinals = <TransferProgress>[];
      final sync = await const MultiPanelSyncCoordinator().execute(
        targetPanelIds: targetIds,
        analyzeTarget: (panelId) async => [syncItem(panelId)],
        previewTarget: (_, items) async => items,
        executeTarget: (_, items) async => SyncExecutionResult(
          createdFiles: items.length,
          updatedFiles: 0,
          failedFiles: 0,
          cancelled: false,
        ),
        publishFinalProgress: syncFinals.add,
      );
      expect(sync.successfulTargetCount, 4);
      expect(syncFinals, hasLength(1));
      expect(syncFinals.single.state, TransferState.completed);
      expect(syncFinals.single.totalFiles, 4);

      expect(
        PanelDragPolicy.resolveTarget(
          sourcePanelId: PanelId.a,
          targetPanelId: fourth,
          entryCount: 2,
        ),
        fourth,
      );
      expect(
        PanelDragPolicy.resolveTarget(
          sourcePanelId: PanelId.a,
          targetPanelId: PanelId.a,
          entryCount: 2,
        ),
        isNull,
      );
    },
  );
}
