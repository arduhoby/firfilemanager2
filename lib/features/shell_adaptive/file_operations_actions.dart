import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/storage/models/file_entry.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/platform/native_file_info_service.dart';
import '../../core/storage/storage_provider_service.dart';
import '../file_operations/archive_service.dart';
import '../file_operations/file_open_service.dart';
import '../file_operations/file_operations_service.dart';
import '../file_operations/file_operations_state.dart';
import '../file_operations/multi_panel_sync_coordinator.dart';
import '../file_operations/multi_panel_transfer_coordinator.dart';
import '../file_operations/panel_drag_policy.dart';
import '../file_operations/panel_target_selection.dart';
import '../file_operations/sync_models.dart';
import '../file_operations/sync_job_models.dart';
import '../file_operations/sync_repositories.dart';
import '../file_operations/sync_scheduler.dart';
import 'panel_controller.dart';
import 'panel_target_selector_dialog.dart';
import 'multi_panel_transfer_result_dialog.dart';
import 'multi_panel_sync_result_dialog.dart';
import 'sync_preview_dialog.dart';
import 'sync_job_dialog.dart';
import '../../core/storage/models/transfer_progress.dart';
import '../../core/settings/recent_service.dart';
import '../../core/settings/settings_provider.dart';
import '../file_operations/file_chunk_service.dart';
import '../file_operations/mac_app_picker_dialog.dart';
import 'flying_file_animation.dart';

part 'file_operations_actions.g.dart';

/// Actions provider that bridges UI interactions (context menu, dialogs)
/// with the [FileOperationsService].
///
/// Handles clipboard operations, rename/delete/new folder dialogs,
/// and properties display.
@Riverpod(keepAlive: true)
class FileOperationsActions extends _$FileOperationsActions {
  @override
  void build() {
    // Service provider - no state.
  }

  PanelState _panelState(PanelId panelId) =>
      ref.read(panelStateProvider(panelId));

  PanelId _otherPanelId(PanelId sourcePanelId) => ref
      .read(panelWorkspaceProvider)
      .panelOrder
      .firstWhere((panelId) => panelId != sourcePanelId);

  void _triggerAnimation(
    BuildContext context,
    PanelId activeSide,
    TransferOperation operation,
    bool isDir, {
    PanelId? destinationPanelId,
  }) {
    if (!context.mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final workspace = ref.read(panelWorkspaceProvider);
    final sourceIndex = workspace.panelOrder.indexOf(activeSide);
    final sourceX = sourceIndex < 0
        ? screenWidth * 0.5
        : screenWidth * ((sourceIndex + 0.5) / workspace.panelCount);
    final destinationId = destinationPanelId ?? _otherPanelId(activeSide);
    final destinationIndex = workspace.panelOrder.indexOf(destinationId);
    final destinationX =
        screenWidth * ((destinationIndex + 0.5) / workspace.panelCount);

    final start = Offset(sourceX, screenHeight * 0.5);
    final end = operation == TransferOperation.delete
        ? Offset(screenWidth * 0.5, screenHeight - 50)
        : Offset(destinationX, screenHeight * 0.5);

    final icon = operation == TransferOperation.delete
        ? Icons.delete_outline
        : (isDir ? Icons.folder : Icons.insert_drive_file);

    final color = operation == TransferOperation.delete
        ? Colors.red
        : Theme.of(context).colorScheme.primary;

    FlyingFileAnimation.show(
      context,
      start: start,
      end: end,
      icon: icon,
      color: color,
    );
  }

  StorageProvider _getProviderForSide(PanelId side) {
    final panelState = _panelState(side);

    if (panelState.activeTab.providerId == 'local') {
      return ref.read(localStorageProviderProvider);
    }

    final provider = ref.read(
      storageProviderRegistryProvider,
    )[panelState.activeTab.providerId];
    if (provider == null) {
      throw Exception('Connection is not active or disconnected.');
    }
    return provider;
  }

  PanelProviderStatus _providerStatus(String providerId) {
    final provider = ref.read(storageProviderRegistryProvider)[providerId];
    if (providerId == 'local') {
      return PanelProviderStatus(
        displayName: provider?.displayName ?? 'Local',
        isAvailable: true,
      );
    }
    return PanelProviderStatus(
      displayName: provider?.displayName ?? providerId,
      isAvailable: provider?.isConnected ?? false,
    );
  }

  Future<List<PanelId>> _selectTargetPanels(
    BuildContext context,
    PanelId sourcePanelId,
    PanelTargetOperation operation, {
    bool allowMultiple = true,
    bool Function(TabState targetState)? targetSupported,
    bool allowSameEndpoint = false,
  }) async {
    final workspace = ref.read(panelWorkspaceProvider);
    final catalog = PanelTargetCatalog.fromWorkspace(
      workspace: workspace,
      sourcePanelId: sourcePanelId,
      providerStatus: _providerStatus,
      targetSupported: targetSupported,
      allowSameEndpoint: allowSameEndpoint,
    );

    if (!PanelTargetSelectionPolicy.shouldShowSelector(workspace.panelCount)) {
      return catalog.selectableTargets.length == 1
          ? [catalog.selectableTargets.single.panelId]
          : const [];
    }
    if (!context.mounted) return const [];

    final selectedPanelIds = await showDialog<List<PanelId>>(
      context: context,
      builder: (context) => PanelTargetSelectorDialog(
        catalog: catalog,
        operation: operation,
        allowMultiple: allowMultiple,
      ),
    );
    return selectedPanelIds ?? const [];
  }

  Future<List<PanelId>> _selectArchiveTargetPanels(
    BuildContext context,
    PanelId sourcePanelId,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final sourceState = _panelState(sourcePanelId);
    if (sourceState.activeTab.providerId != 'local') {
      _showErrorSnackBar(context, l10n.archiveLocalSourceRequired);
      return const [];
    }

    // Compression is safe in the source directory: the manifest is collected
    // before the output file is created. In the normal two-panel layout this
    // also prevents an unrelated or remote second panel from turning the
    // command into a silent no-op.
    final workspace = ref.read(panelWorkspaceProvider);
    if (!PanelTargetSelectionPolicy.shouldShowSelector(workspace.panelCount)) {
      return [sourcePanelId];
    }

    return _selectTargetPanels(
      context,
      sourcePanelId,
      PanelTargetOperation.compress,
      targetSupported: (targetState) => targetState.providerId == 'local',
      allowSameEndpoint: true,
    );
  }

  /// Copy selected entries to clipboard
  void copyToClipboard(PanelId side, List<FileEntry> entries) {
    final panelState = _panelState(side);
    final providerId = panelState.activeTab.providerId;
    final paths = entries.map((e) => e.path).toList();
    ref.read(fileClipboardProvider.notifier).copy(paths, side, providerId);
  }

  /// Cut selected entries to clipboard
  void cutToClipboard(PanelId side, List<FileEntry> entries) {
    final panelState = _panelState(side);
    final providerId = panelState.activeTab.providerId;
    final paths = entries.map((e) => e.path).toList();
    ref.read(fileClipboardProvider.notifier).cut(paths, side, providerId);
  }

  /// Paste from clipboard to the given panel's current directory
  Future<void> paste(BuildContext context, PanelId destSide) async {
    final destState = _panelState(destSide);

    final provider = _getProviderForSide(destSide);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    final clipboard = ref.read(fileClipboardProvider);
    if (clipboard != null && clipboard.sourcePaths.isNotEmpty) {
      final sourceSide = clipboard.sourcePanelId;
      final operation = clipboard.operation == ClipboardOperation.cut
          ? TransferOperation.move
          : TransferOperation.copy;
      // We assume it might be a dir, but it's just for icon
      _triggerAnimation(
        context,
        sourceSide,
        operation,
        false,
        destinationPanelId: destSide,
      );
    }

    try {
      await service.paste(
        destProvider: provider,
        destPath: destState.activeTab.currentPath,
      );
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }

    // Refresh the destination panel
    await ref.read(panelControllerProvider.notifier).refresh(destSide);
  }

  Future<void> splitFile(
    BuildContext context,
    PanelId side,
    FileEntry entry,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu işlem aynı panel içinde gerçekleştirilir.'),
      ),
    );
    final settings = ref.read(settingsProvider);
    final progress = ref.read(operationProgressProvider.notifier);
    try {
      final count = await const FileChunkService().split(
        entry: entry,
        partSizeBytes: settings.filePartSizeMb * 1024 * 1024,
        onProgress: progress.setProgress,
      );
      await ref.read(panelControllerProvider.notifier).refresh(side);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dosya $count parçaya ayrıldı.')),
        );
      }
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error.toString());
    }
  }

  Future<void> mergeFileParts(
    BuildContext context,
    PanelId side,
    List<FileEntry> entries,
  ) async {
    final panel = _panelState(side);
    if (panel.activeTab.providerId != 'local') {
      _showErrorSnackBar(context, 'WebDAV panelinde parçalar birleştirilmez.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu işlem aynı panel içinde gerçekleştirilir.'),
      ),
    );
    final progress = ref.read(operationProgressProvider.notifier);
    try {
      final output = await const FileChunkService().merge(
        entries: entries,
        onProgress: progress.setProgress,
      );
      await ref.read(panelControllerProvider.notifier).refresh(side);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Parçalar birleştirildi: ${File(output).uri.pathSegments.last}',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error.toString());
    }
  }

  /// Show rename dialog
  Future<void> showRenameDialog(
    BuildContext context,
    PanelId side,
    FileEntry entry,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final controller = TextEditingController(text: entry.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.propertiesName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result.isEmpty || result == entry.name) return;

    final provider = _getProviderForSide(side);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    try {
      await service.rename(provider: provider, entry: entry, newName: result);
      await ref.read(panelControllerProvider.notifier).refresh(side);
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// Show delete confirmation dialog
  Future<void> showDeleteDialog(
    BuildContext context,
    PanelId side,
    List<FileEntry> entries,
  ) async {
    await _executeDeleteOrAsk(context, side, entries);
  }

  /// Unified delete execution: asks only if a directory is NOT empty.
  Future<void> _executeDeleteOrAsk(
    BuildContext context,
    PanelId side,
    List<FileEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final l10n = gen.AppLocalizations.of(context)!;
    final provider = _getProviderForSide(side);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    bool wipeSelected = false;
    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l10n.confirmDeleteTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seçili öğeleri silmek istediğinizden emin misiniz?',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: wipeSelected,
                        onChanged: (val) {
                          setState(() {
                            wipeSelected = val ?? false;
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Kalıcı sil (wipe - üzerine yazarak güvenli sil)',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.actionCancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.actionDelete),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != true) return;

    try {
      if (!context.mounted) return;

      await service.delete(
        provider: provider,
        entries: entries,
        wipe: wipeSelected,
      );

      if (context.mounted) {
        _triggerAnimation(
          context,
          side,
          TransferOperation.delete,
          entries.isNotEmpty && entries.first.isDirectory,
        );
      }

      // Clear selection and refresh

      await ref.read(panelControllerProvider.notifier).refresh(side);
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// Show new folder dialog
  Future<void> showNewFolderDialog(BuildContext context, PanelId side) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionNewFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.propertiesName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result.isEmpty) return;

    final panelState = _panelState(side);

    final provider = _getProviderForSide(side);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    try {
      await service.mkdir(
        provider: provider,
        parentPath: panelState.activeTab.currentPath,
        name: result,
      );
      await ref.read(panelControllerProvider.notifier).refresh(side);
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// Show new file dialog
  Future<void> showNewFileDialog(BuildContext context, PanelId side) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Dosya'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.propertiesName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result.isEmpty) return;

    final panelState = _panelState(side);

    final provider = _getProviderForSide(side);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    try {
      await service.createFile(
        provider: provider,
        parentPath: panelState.activeTab.currentPath,
        name: result,
      );
      await ref.read(panelControllerProvider.notifier).refresh(side);

      // Open the created file
      final newFilePath = provider.joinPath(
        panelState.activeTab.currentPath,
        result,
      );
      final fileOpenService = ref.read(fileOpenServiceProvider.notifier);
      await fileOpenService.openWithDefault(newFilePath);
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, e.toString());
      }
    }
  }

  /// Show file properties dialog
  Future<void> showPropertiesDialog(
    BuildContext context,
    FileEntry entry,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;

    if (await NativeFileInfoService.show(entry.path)) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionProperties),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propertyRow(l10n.propertiesName, entry.name),
            _propertyRow(l10n.propertiesPath, entry.path),
            _propertyRow(
              l10n.propertiesType,
              entry.isDirectory ? l10n.propertiesFolder : l10n.propertiesFile,
            ),
            if (!entry.isDirectory)
              _propertyRow(l10n.propertiesSize, _formatSize(entry.size)),
            if (entry.modified != null)
              _propertyRow(l10n.propertiesModified, entry.modified.toString()),
            if (entry.permissions != null)
              _propertyRow(l10n.propertiesPermissions, entry.permissions!),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }

  /// Copy selected entries from one source panel to selected target panels.
  Future<void> copyToOtherPanel(BuildContext context, PanelId sourceSide) =>
      _runMultiPanelTransfer(context, sourceSide, TransferOperation.copy);

  /// Move selected entries to every selected target, then delete the source.
  Future<void> moveToOtherPanel(BuildContext context, PanelId sourceSide) =>
      _runMultiPanelTransfer(context, sourceSide, TransferOperation.move);

  Future<void> _runMultiPanelTransfer(
    BuildContext context,
    PanelId sourceSide,
    TransferOperation operation,
  ) async {
    final sourceState = _panelState(sourceSide);
    if (!sourceState.activeTab.hasSelection) return;

    final targetOperation = operation == TransferOperation.move
        ? PanelTargetOperation.move
        : PanelTargetOperation.copy;
    final destinationPanelIds = await _selectTargetPanels(
      context,
      sourceSide,
      targetOperation,
    );
    if (destinationPanelIds.isEmpty || !context.mounted) return;

    final workspaceSnapshot = ref.read(panelWorkspaceProvider);
    final destinationPaths = <PanelId, String>{
      for (final panelId in destinationPanelIds)
        panelId: workspaceSnapshot.panel(panelId).activeTab.currentPath,
    };
    final l10n = gen.AppLocalizations.of(context)!;
    final actionLabel = operation == TransferOperation.move
        ? l10n.actionMove
        : l10n.actionCopy;
    if (destinationPanelIds.length == 1) {
      final destinationPanelId = destinationPanelIds.single;
      final destinationPath = await _showTransferDialog(
        context,
        '$actionLabel (${sourceState.activeTab.selectionCount} items)',
        actionLabel,
        destinationPaths[destinationPanelId]!,
      );
      if (destinationPath == null ||
          destinationPath.isEmpty ||
          !context.mounted) {
        return;
      }
      destinationPaths[destinationPanelId] = destinationPath;
    }

    final sourceProvider = _getProviderForSide(sourceSide);
    final destinationProviders = <PanelId, StorageProvider?>{};
    for (final panelId in destinationPanelIds) {
      try {
        destinationProviders[panelId] = _getProviderForSide(panelId);
      } catch (_) {
        destinationProviders[panelId] = null;
      }
    }
    final service = ref.read(fileOperationsServiceProvider.notifier);
    final entries = sourceState.activeTab.selectedEntries;
    final firstDestinationPanelId = destinationPanelIds.first;
    _triggerAnimation(
      context,
      sourceSide,
      operation,
      entries.isNotEmpty && entries.first.isDirectory,
      destinationPanelId: firstDestinationPanelId,
    );

    const coordinator = MultiPanelTransferCoordinator();
    final result = await coordinator.execute(
      operation: operation,
      targetPanelIds: destinationPanelIds,
      transferTarget: (panelId) {
        final destinationProvider = destinationProviders[panelId];
        if (destinationProvider == null) {
          throw StateError('Destination panel connection is unavailable.');
        }
        return service.copy(
          sourceProvider: sourceProvider,
          entries: entries,
          destProvider: destinationProvider,
          destPath: destinationPaths[panelId]!,
          isMove: operation == TransferOperation.move,
          publishCompletion: false,
          overwriteCallback: (fileName) {
            if (!context.mounted) return Future<String?>.value();
            return _showOverwriteDialog(context, fileName);
          },
        );
      },
      deleteSource: operation == TransferOperation.move
          ? () => service.delete(
              provider: sourceProvider,
              entries: entries,
              hideProgress: true,
            )
          : null,
      publishFinalProgress: ref
          .read(operationProgressProvider.notifier)
          .setProgress,
    );

    final currentWorkspace = ref.read(panelWorkspaceProvider);
    for (final panelId in result.successfulPanelIds) {
      if (currentWorkspace.panels.containsKey(panelId)) {
        await ref.read(panelControllerProvider.notifier).refresh(panelId);
      }
    }
    if (result.sourceDeleted &&
        currentWorkspace.panels.containsKey(sourceSide)) {
      ref.read(panelWorkspaceProvider.notifier).clearSelection(sourceSide);
      await ref.read(panelControllerProvider.notifier).refresh(sourceSide);
    }

    if (!context.mounted) return;
    if (result.isSuccessful) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.multiTransferSuccess(result.successfulTargetCount),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => MultiPanelTransferResultDialog(
        result: result,
        panelNumbers: {
          for (final panelId in destinationPanelIds)
            panelId: workspaceSnapshot.panelOrder.indexOf(panelId) + 1,
        },
      ),
    );
  }

  /// Shows a dialog asking what to do when a destination file already exists.
  /// Returns: 'overwrite', 'rename', 'skip', or null (cancel all).
  Future<String?> _showOverwriteDialog(
    BuildContext context,
    String fileName,
  ) async {
    final theme = Theme.of(context);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 10),
            const Text('Dosya Zaten Var'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hedef konumda aynı isimde bir dosya mevcut:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('Ne yapmak istersiniz?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: const Text('Atla'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'rename'),
            icon: const Icon(Icons.drive_file_rename_outline, size: 16),
            label: const Text('Yeniden Adlandır'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, 'overwrite'),
            icon: const Icon(Icons.file_copy_outlined, size: 16),
            label: const Text('Üzerine Yaz'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTransferDialog(
    BuildContext context,
    String title,
    String buttonLabel,
    String initialDestPath,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialDestPath);
    final theme = Theme.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.drive_file_move_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Destination Path:',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.folder_open, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please review the destination path before proceeding.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(Icons.check, size: 18),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  /// Synchronize one source panel to every selected target panel.
  Future<void> syncPanels(BuildContext context, PanelId sourceSide) async {
    final destinationPanelIds = await _selectTargetPanels(
      context,
      sourceSide,
      PanelTargetOperation.sync,
      allowMultiple: true,
    );
    if (destinationPanelIds.isEmpty || !context.mounted) return;

    final workspaceSnapshot = ref.read(panelWorkspaceProvider);
    final sourceState = workspaceSnapshot.panel(sourceSide);
    final sourcePath = sourceState.activeTab.currentPath;
    final sourceProvider = _getProviderForSide(sourceSide);
    final destinationStates = {
      for (final panelId in destinationPanelIds)
        panelId: workspaceSnapshot.panel(panelId),
    };
    final destinationProviders = <PanelId, StorageProvider?>{};
    for (final panelId in destinationPanelIds) {
      try {
        destinationProviders[panelId] = _getProviderForSide(panelId);
      } catch (_) {
        destinationProviders[panelId] = null;
      }
    }
    final service = ref.read(fileOperationsServiceProvider.notifier);
    const coordinator = MultiPanelSyncCoordinator();
    final result = await coordinator.execute(
      targetPanelIds: destinationPanelIds,
      analyzeTarget: (panelId) {
        final destinationProvider = destinationProviders[panelId];
        if (destinationProvider == null) {
          throw StateError('Destination panel connection is unavailable.');
        }
        return service.analyzeSync(
          sourceProvider: sourceProvider,
          sourcePath: sourcePath,
          destProvider: destinationProvider,
          destPath: destinationStates[panelId]!.activeTab.currentPath,
          publishCompletion: false,
        );
      },
      previewTarget: (panelId, syncItems) async {
        if (!context.mounted) return null;
        final destinationState = destinationStates[panelId]!;
        final destinationProvider = destinationProviders[panelId]!;
        final destinationPath = destinationState.activeTab.currentPath;
        return showDialog<List<SyncItem>>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => SyncPreviewDialog(
            sourcePath: sourcePath,
            destPath: destinationPath,
            items: syncItems,
            onSave: (selection) => _saveSyncJob(
              dialogContext,
              sourceProviderId: sourceState.activeTab.providerId,
              sourcePath: sourcePath,
              sourceDisplayName: sourceProvider.displayName,
              destinationProviderId: destinationState.activeTab.providerId,
              destinationPath: destinationPath,
              destinationDisplayName: destinationProvider.displayName,
              selection: selection,
            ),
          ),
        );
      },
      executeTarget: (panelId, selectedItems) => service.executeSync(
        sourceProvider: sourceProvider,
        destProvider: destinationProviders[panelId]!,
        destPath: destinationStates[panelId]!.activeTab.currentPath,
        selectedItems: selectedItems,
        publishCompletion: false,
      ),
      publishFinalProgress: ref
          .read(operationProgressProvider.notifier)
          .setProgress,
    );

    final currentWorkspace = ref.read(panelWorkspaceProvider);
    if (currentWorkspace.panels.containsKey(sourceSide)) {
      await ref.read(panelControllerProvider.notifier).refresh(sourceSide);
    }
    for (final panelId in result.refreshedPanelIds) {
      if (ref.read(panelWorkspaceProvider).panels.containsKey(panelId)) {
        await ref.read(panelControllerProvider.notifier).refresh(panelId);
      }
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => MultiPanelSyncResultDialog(
        result: result,
        panelNumbers: {
          for (final panelId in destinationPanelIds)
            panelId: workspaceSnapshot.panelOrder.indexOf(panelId) + 1,
        },
      ),
    );
  }

  Future<void> _saveSyncJob(
    BuildContext context, {
    required String sourceProviderId,
    required String sourcePath,
    required String sourceDisplayName,
    required String destinationProviderId,
    required String destinationPath,
    required String destinationDisplayName,
    required SyncPreviewSelection selection,
  }) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final editorResult = await showDialog<SyncJobEditorResult>(
      context: context,
      builder: (context) => SyncJobDialog(
        suggestedName: '$sourceDisplayName → $destinationDisplayName',
      ),
    );
    if (editorResult == null || !context.mounted) return;

    final sourceVolumeIdentity = await _resolveVolumeIdentity(
      sourceProviderId,
      sourcePath,
    );
    final destinationVolumeIdentity = await _resolveVolumeIdentity(
      destinationProviderId,
      destinationPath,
    );
    if (!context.mounted) return;

    final repository = ref.read(syncJobRepositoryProvider.notifier);
    SyncJob? createdJob;
    try {
      createdJob = await repository.create(
        name: editorResult.name,
        source: SyncEndpoint(
          providerId: sourceProviderId,
          path: sourcePath,
          displayName: sourceDisplayName,
          volumeIdentity: sourceVolumeIdentity,
        ),
        destination: SyncEndpoint(
          providerId: destinationProviderId,
          path: destinationPath,
          displayName: destinationDisplayName,
          volumeIdentity: destinationVolumeIdentity,
        ),
        selectionPolicy: selection.policy,
        includedPaths: selection.includedPaths,
        excludedPaths: selection.excludedPaths,
        schedule: editorResult.schedule,
        enabled: editorResult.enabled,
      );
      await ref.read(syncSchedulerProvider.notifier).apply(createdJob);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.syncJobSaved(createdJob.name))),
      );
    } on SyncJobNameConflict catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.syncJobNameConflict(error.name)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (error) {
      if (createdJob != null) {
        try {
          await ref.read(syncSchedulerProvider.notifier).remove(createdJob.id);
          await repository.delete(createdJob.id);
        } catch (_) {
          // Preserve the scheduling error; cleanup is best effort.
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<String?> _resolveVolumeIdentity(String providerId, String path) async {
    if (!Platform.isAndroid || providerId != 'local') return null;
    return const MethodChannel(
      'fir_file_manager/file_actions',
    ).invokeMethod<String>('storageIdentity', {'path': path});
  }

  /// Handle Drag and Drop between panels (instant copy)
  Future<void> handleDragAndDrop(
    BuildContext context,
    PanelId sourceSide,
    PanelId destSide,
    List<FileEntry> entries,
  ) async {
    final resolvedDestination = PanelDragPolicy.resolveTarget(
      sourcePanelId: sourceSide,
      targetPanelId: destSide,
      entryCount: entries.length,
    );
    if (resolvedDestination == null) return;

    final destState = _panelState(resolvedDestination);

    final destPath = destState.activeTab.currentPath;

    final sourceProvider = _getProviderForSide(sourceSide);
    final destProvider = _getProviderForSide(resolvedDestination);
    final service = ref.read(fileOperationsServiceProvider.notifier);

    _triggerAnimation(
      context,
      sourceSide,
      TransferOperation.copy,
      entries.isNotEmpty && entries.first.isDirectory,
      destinationPanelId: resolvedDestination,
    );

    await service.copy(
      sourceProvider: sourceProvider,
      entries: entries,
      destProvider: destProvider,
      destPath: destPath,
    );

    await ref
        .read(panelControllerProvider.notifier)
        .refresh(resolvedDestination);
  }

  /// Delete selected entries from the given panel
  Future<void> deleteSelected(BuildContext context, PanelId side) async {
    final state = _panelState(side);

    final entries = state.activeTab.selectedEntries;
    if (entries.isEmpty) return;

    await _executeDeleteOrAsk(context, side, entries);
  }

  /// Open a file with the system default application.
  Future<void> openWithDefault(
    BuildContext context,
    PanelId side,
    FileEntry entry,
  ) async {
    final archiveService = ref.read(archiveServiceProvider.notifier);
    if (archiveService.isArchive(entry.path)) {
      await extractArchive(context, side, entry);
      return;
    }

    final openService = ref.read(fileOpenServiceProvider.notifier);
    final success = await openService.openWithDefault(entry.path);
    if (success) {
      await ref.read(recentServiceProvider.notifier).addRecentFile(entry.path);
    } else if (context.mounted) {
      _showErrorSnackBar(context, 'Açılamadı: ${entry.name}');
    }
  }

  /// Edit a file with the editor selected for the current platform.
  Future<void> editFile(BuildContext context, FileEntry entry) async {
    final openService = ref.read(fileOpenServiceProvider.notifier);
    final result = await openService.edit(entry.path);

    switch (result) {
      case EditFileResult.opened:
        await ref
            .read(recentServiceProvider.notifier)
            .addRecentFile(entry.path);
      case EditFileResult.downloadPageOpened:
        if (context.mounted) {
          _showWarningSnackBar(
            context,
            'Kate kurulu değil. Resmî indirme sayfası açıldı.',
          );
        }
      case EditFileResult.failed:
        if (context.mounted) {
          _showErrorSnackBar(
            context,
            'Sistem düzenleyicisiyle açılamadı: ${entry.name}',
          );
        }
    }
  }

  /// Open a file with a known application path.
  Future<void> openWithApplication(
    BuildContext context,
    FileEntry entry,
    String applicationPath,
  ) async {
    final openService = ref.read(fileOpenServiceProvider.notifier);
    final success = await openService.openWithApplication(
      entry.path,
      applicationPath,
    );
    if (success) {
      await ref
          .read(recentServiceProvider.notifier)
          .addRecentApp(applicationPath);
      await ref.read(recentServiceProvider.notifier).addRecentFile(entry.path);
    } else if (context.mounted) {
      _showWarningSnackBar(context, 'Şununla açılamadı: ${entry.name}');
    }
  }

  /// Ask the user to choose an application and open the file.
  Future<void> chooseAppAndOpen(BuildContext context, FileEntry entry) async {
    if (Platform.isMacOS) {
      final applicationPath = await MacAppPickerDialog.show(context);
      if (applicationPath == null || applicationPath.isEmpty) return;
      if (!context.mounted) return;
      await openWithApplication(context, entry, applicationPath);
      return;
    }

    final openService = ref.read(fileOpenServiceProvider.notifier);
    final success = await openService.chooseAppAndOpen(entry.path);
    if (success) {
      await ref.read(recentServiceProvider.notifier).addRecentFile(entry.path);
    } else if (context.mounted) {
      _showWarningSnackBar(
        context,
        'Şununla açılamadı veya işlem iptal edildi: ${entry.name}',
      );
    }
  }

  /// Reveal a file in Finder/Explorer
  Future<void> revealInFileManager(
    BuildContext context,
    FileEntry entry,
  ) async {
    final openService = ref.read(fileOpenServiceProvider.notifier);
    final success = await openService.revealInFileManager(entry.path);

    if (!success && context.mounted) {
      _showErrorSnackBar(context, 'Failed to reveal: ${entry.name}');
    }
  }

  Future<MultiPanelTransferResult> _compressToPanels({
    required List<FileEntry> entries,
    required List<PanelId> destinationPanelIds,
    required Map<PanelId, String> destinationPaths,
    required String archiveName,
    required ArchiveFormat format,
    String? password,
  }) async {
    final archiveService = ref.read(archiveServiceProvider.notifier);
    final progressNotifier = ref.read(operationProgressProvider.notifier);
    final manifest = await archiveService.createManifest(entries);
    await archiveService.checkManifestAvailableSpace(
      manifest: manifest,
      destinationDirectories: destinationPaths.values,
      format: format,
    );

    var firstTargetAttempted = false;
    String? sourceArchivePath;

    return const MultiPanelTransferCoordinator().execute(
      operation: TransferOperation.zip,
      targetPanelIds: destinationPanelIds,
      transferTarget: (panelId) async {
        final destinationDirectory = destinationPaths[panelId]!;
        final isFirstTarget = !firstTargetAttempted;
        firstTargetAttempted = true;
        TransferProgress? finalProgress;

        if (isFirstTarget) {
          await for (final progress in archiveService.compressManifest(
            manifest: manifest,
            destDir: destinationDirectory,
            archiveName: archiveName,
            format: format,
            password: password,
          )) {
            if (progress.isFinished) {
              finalProgress = progress;
            } else {
              progressNotifier.setProgress(progress);
            }
          }
          if (finalProgress?.state == TransferState.completed) {
            sourceArchivePath = archiveService.archivePath(
              destinationDirectory: destinationDirectory,
              archiveName: archiveName,
              format: format,
            );
          }
        } else if (sourceArchivePath != null) {
          await for (final progress in archiveService.copyArchiveTo(
            manifest: manifest,
            sourceArchivePath: sourceArchivePath!,
            destDir: destinationDirectory,
            archiveName: archiveName,
            format: format,
          )) {
            if (progress.isFinished) {
              finalProgress = progress;
            } else {
              progressNotifier.setProgress(progress);
            }
          }
        } else {
          finalProgress = TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.failed,
            error:
                'İlk hedef arşivi oluşturamadı; diğer hedeflere kopyalama yapılmadı.',
          );
        }

        return finalProgress ??
            TransferProgress(
              operation: TransferOperation.zip,
              state: TransferState.failed,
              error: 'Arşiv işlemi nihai sonuç üretmeden tamamlandı.',
            );
      },
      publishFinalProgress: progressNotifier.setProgress,
    );
  }

  /// Compress selected entries into an archive
  Future<void> compressEntries(
    BuildContext context,
    PanelId side,
    List<FileEntry> entries,
    ArchiveFormat format,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final destinationPanelIds = await _selectArchiveTargetPanels(context, side);
    if (destinationPanelIds.isEmpty || !context.mounted) return;
    final workspaceSnapshot = ref.read(panelWorkspaceProvider);
    final destinationPaths = <PanelId, String>{
      for (final panelId in destinationPanelIds)
        panelId: workspaceSnapshot.panel(panelId).activeTab.currentPath,
    };

    // Suggest archive name based on first entry or selection
    final suggestedName = entries.length == 1 ? entries.first.name : 'archive';

    final controller = TextEditingController(text: suggestedName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionCompress),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.propertiesName,
            suffixText: switch (format) {
              ArchiveFormat.zip => '.zip',
              ArchiveFormat.tar => '.tar',
              ArchiveFormat.tarGz => '.tar.gz',
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result == null || result.isEmpty) return;
    if (!context.mounted) return;

    // Show one animation at the start; completion is published only once.
    _triggerAnimation(
      context,
      side,
      TransferOperation.copy,
      entries.isNotEmpty && entries.first.isDirectory,
      destinationPanelId: destinationPanelIds.first,
    );

    MultiPanelTransferResult multiResult;
    try {
      multiResult = await _compressToPanels(
        entries: entries,
        destinationPanelIds: destinationPanelIds,
        destinationPaths: destinationPaths,
        archiveName: result,
        format: format,
      );
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error.toString());
      return;
    }

    final currentWorkspace = ref.read(panelWorkspaceProvider);
    for (final panelId in multiResult.successfulPanelIds) {
      if (currentWorkspace.panels.containsKey(panelId)) {
        await ref.read(panelControllerProvider.notifier).refresh(panelId);
      }
    }

    if (!context.mounted) return;
    if (multiResult.isSuccessful) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.multiArchiveSuccess(multiResult.successfulTargetCount),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => MultiPanelTransferResultDialog(
        result: multiResult,
        panelNumbers: {
          for (final panelId in destinationPanelIds)
            panelId: workspaceSnapshot.panelOrder.indexOf(panelId) + 1,
        },
      ),
    );
  }

  /// Compress entries into a password-protected ZIP.
  /// Shows an archive name dialog + password dialog before compressing.
  Future<void> compressEntriesWithPassword(
    BuildContext context,
    PanelId side,
    List<FileEntry> entries,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final destinationPanelIds = await _selectArchiveTargetPanels(context, side);
    if (destinationPanelIds.isEmpty || !context.mounted) return;
    final workspaceSnapshot = ref.read(panelWorkspaceProvider);
    final destinationPaths = <PanelId, String>{
      for (final panelId in destinationPanelIds)
        panelId: workspaceSnapshot.panel(panelId).activeTab.currentPath,
    };

    // 1. Ask for archive name
    final suggestedName = entries.length == 1 ? entries.first.name : 'archive';
    final nameCtrl = TextEditingController(text: suggestedName);
    final archiveName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şifreli ZIP'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Arşiv adı',
            suffixText: '.zip',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (archiveName == null || archiveName.isEmpty) return;
    if (!context.mounted) return;

    // 2. Ask for password (with confirmation)
    final pwdCtrl = TextEditingController();
    final pwd2Ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        bool obscure = true;
        return StatefulBuilder(
          builder: (ctx2, setSt) => AlertDialog(
            title: const Text('Şifre belirleyin'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtrl,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Şifre',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pwd2Ctrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Şifreyi tekrar girin',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(
                onPressed: () {
                  if (pwdCtrl.text != pwd2Ctrl.text) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      const SnackBar(content: Text('Şifreler eşleşmiyor!')),
                    );
                    return;
                  }
                  if (pwdCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(
                      const SnackBar(content: Text('Şifre boş olamaz!')),
                    );
                    return;
                  }
                  Navigator.pop(ctx2, pwdCtrl.text);
                },
                child: Text(l10n.actionCompress),
              ),
            ],
          ),
        );
      },
    );
    pwdCtrl.dispose();
    pwd2Ctrl.dispose();
    if (password == null) return;

    // 3. Use the same manifest, producer and fan-out path as normal archives.
    MultiPanelTransferResult multiResult;
    try {
      multiResult = await _compressToPanels(
        entries: entries,
        destinationPanelIds: destinationPanelIds,
        destinationPaths: destinationPaths,
        archiveName: archiveName,
        format: ArchiveFormat.zip,
        password: password,
      );
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error.toString());
      return;
    }

    final currentWorkspace = ref.read(panelWorkspaceProvider);
    for (final panelId in multiResult.successfulPanelIds) {
      if (currentWorkspace.panels.containsKey(panelId)) {
        await ref.read(panelControllerProvider.notifier).refresh(panelId);
      }
    }

    if (!context.mounted) return;
    if (multiResult.isSuccessful) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.multiArchiveSuccess(multiResult.successfulTargetCount),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => MultiPanelTransferResultDialog(
        result: multiResult,
        panelNumbers: {
          for (final panelId in destinationPanelIds)
            panelId: workspaceSnapshot.panelOrder.indexOf(panelId) + 1,
        },
      ),
    );
  }

  Future<void> extractArchive(
    BuildContext context,
    PanelId side,
    FileEntry entry,
  ) async {
    final destinationPanelId = _otherPanelId(side);
    final destPanelState = _panelState(destinationPanelId);

    final archiveService = ref.read(archiveServiceProvider.notifier);

    // 1. Check if encrypted
    final isEncrypted = await archiveService.isEncryptedZip(entry.path);
    if (!context.mounted) return;
    String? password;

    if (isEncrypted) {
      // Ask for password
      final pwdCtrl = TextEditingController();
      bool obscure = true;
      password = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setSt) => AlertDialog(
            title: const Text('Şifreli Arşiv'),
            content: TextField(
              controller: pwdCtrl,
              obscureText: obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Şifre',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setSt(() => obscure = !obscure),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx2, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx2, pwdCtrl.text),
                child: const Text('Tamam'),
              ),
            ],
          ),
        ),
      );
      pwdCtrl.dispose();

      // If user cancelled password dialog
      if (password == null || password.isEmpty) return;
    }

    try {
      final progressNotifier = ref.read(operationProgressProvider.notifier);

      Stream<TransferProgress> progressStream;
      if (isEncrypted && password != null) {
        progressStream = archiveService.extract(
          archivePath: entry.path,
          destDir: destPanelState.activeTab.currentPath,
          password: password,
        );
      } else {
        progressStream = archiveService.extract(
          archivePath: entry.path,
          destDir: destPanelState.activeTab.currentPath,
        );
      }

      String? lastFile;
      await for (final progress in progressStream) {
        progressNotifier.setProgress(progress);

        // Trigger animation only for new files (avoid spamming)
        if (progress.currentFile != null &&
            progress.currentFile!.name != lastFile &&
            progress.currentFile!.name != 'Done' &&
            context.mounted) {
          lastFile = progress.currentFile!.name;
          _triggerAnimation(context, side, TransferOperation.copy, false);
        }
      }

      progressNotifier.clear();

      await ref
          .read(panelControllerProvider.notifier)
          .refresh(destinationPanelId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Arşiv başarıyla çıkartıldı!')),
        );
      }
    } catch (e) {
      ref.read(operationProgressProvider.notifier).clear();
      if (context.mounted) {
        unawaited(
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Arşiv Hatası'),
              content: Text(e.toString().replaceAll('Exception:', '').trim()),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tamam'),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  /// Check if a file is a supported archive
  bool isArchiveFile(FileEntry entry) {
    if (entry.isDirectory) return false;
    final archiveService = ref.read(archiveServiceProvider.notifier);
    return archiveService.isArchive(entry.path);
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showWarningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  Widget _propertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Show dialog to share a file or folder via SMB
  Future<void> showShareSmbDialog(BuildContext context, FileEntry entry) async {
    // 1. Get local IPs
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    if (ips.isEmpty) ips.add('127.0.0.1');

    // 2. Fetch existing share points from macOS sharing command
    String shareName = entry.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (shareName.isEmpty) shareName = 'shared_folder';
    String relativePath = '';
    bool isShared = false;
    String matchedShareName = shareName;

    try {
      final res = await Process.run('sharing', ['-l']);
      if (res.exitCode == 0) {
        final output = res.stdout as String;
        final lines = output.split('\n');
        String? currentName;
        String? currentPath;

        for (final line in lines) {
          final trimmed = line.trim();
          if (line.startsWith('name:')) {
            currentName = line.split('name:')[1].trim();
          } else if (trimmed.startsWith('path:')) {
            final parsedPath = line.split('path:')[1].trim();
            currentPath = parsedPath;

            if (currentName != null) {
              final ep = entry.path.replaceAll(RegExp(r'/+$'), '');
              final sp = parsedPath.replaceAll(RegExp(r'/+$'), '');
              if (ep == sp) {
                isShared = true;
                matchedShareName = currentName;
                relativePath = '';
                break;
              } else if (ep.startsWith(sp + '/')) {
                isShared = true;
                matchedShareName = currentName;
                relativePath = ep.substring(sp.length);
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    if (context.mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) {
            return _SmbShareDialog(
              entry: entry,
              localIps: ips,
              defaultShareName: shareName,
              matchedShareName: matchedShareName,
              relativePath: relativePath,
              isAlreadyShared: isShared,
            );
          },
        ).then((_) {
          // Automatically refresh panels when the dialog is closed
          for (final panelId in ref.read(panelWorkspaceProvider).panelOrder) {
            ref.read(panelControllerProvider.notifier).refresh(panelId);
          }
        }),
      );
    }
  }
}

class _SmbShareDialog extends StatefulWidget {
  final FileEntry entry;
  final List<String> localIps;
  final String defaultShareName;
  final String matchedShareName;
  final String relativePath;
  final bool isAlreadyShared;

  const _SmbShareDialog({
    required this.entry,
    required this.localIps,
    required this.defaultShareName,
    required this.matchedShareName,
    required this.relativePath,
    required this.isAlreadyShared,
  });

  @override
  State<_SmbShareDialog> createState() => _SmbShareDialogState();
}

class _SmbShareDialogState extends State<_SmbShareDialog> {
  late String _selectedIp;
  bool _isProcessing = false;

  Future<void> _executeSharingCommand({
    required List<String> normalArgs,
    required String privilegeCommand,
  }) async {
    setState(() => _isProcessing = true);
    try {
      // First attempt to execute without sudo (passwordless)
      final res = await Process.run('sharing', normalArgs);
      if (res.exitCode == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Operation completed successfully!')),
          );
          Navigator.pop(context);
        }
        return;
      }

      // If passwordless failed, request administrator privileges
      final privilegedRes = await Process.run('osascript', [
        '-e',
        'do shell script "$privilegeCommand" with administrator privileges',
      ]);
      if (privilegedRes.exitCode == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Operation completed successfully (with admin privileges)!',
              ),
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${privilegedRes.stderr}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIp = widget.localIps.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shareName = widget.isAlreadyShared
        ? widget.matchedShareName
        : widget.defaultShareName;
    final relPath = widget.relativePath.replaceAll('/', '\\');

    // Construct URLs
    final macUrl = 'smb://$_selectedIp/$shareName${widget.relativePath}';
    final winUrl = '\\\\$_selectedIp\\$shareName$relPath';

    final cliCommandSecure =
        'sudo sharing -a "${widget.entry.path}" -n "$shareName"';
    final cliCommandGuest =
        'sudo sharing -a "${widget.entry.path}" -n "$shareName" -g';
    final stopCliCommand = 'sudo sharing -r "$shareName"';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.share, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share via SMB',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(height: 24),

            // IP Selector
            Row(
              children: [
                const Text(
                  'Select IP Address:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedIp,
                  items: widget.localIps.map((ip) {
                    return DropdownMenuItem<String>(value: ip, child: Text(ip));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedIp = val);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Share Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.isAlreadyShared
                    ? Colors.green.withOpacity(0.1)
                    : Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isAlreadyShared ? Colors.green : Colors.amber,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isAlreadyShared
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: widget.isAlreadyShared ? Colors.green : Colors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.isAlreadyShared
                          ? 'This path is active inside the shared folder: "$shareName"'
                          : 'This directory is not shared yet on your Mac.',
                      style: TextStyle(
                        color: widget.isAlreadyShared
                            ? Colors.green[800]
                            : Colors.amber[800],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mac URL Card
            _buildUrlCard(
              title: 'macOS / Linux Link',
              url: macUrl,
              icon: Icons.apple,
            ),
            const SizedBox(height: 12),

            // Windows URL Card
            _buildUrlCard(
              title: 'Windows Network Path',
              url: winUrl,
              icon: Icons.window,
            ),
            const SizedBox(height: 20),

            if (_isProcessing) ...[
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'Processing sharing configuration...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              if (!widget.isAlreadyShared) ...[
                // Share action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        icon: const Icon(Icons.security, size: 16),
                        label: const Text(
                          'Share (Secure)',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          _executeSharingCommand(
                            normalArgs: [
                              '-a',
                              widget.entry.path,
                              '-n',
                              shareName,
                            ],
                            privilegeCommand:
                                'sharing -a \\"${widget.entry.path}\\" -n \\"$shareName\\"',
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: theme.colorScheme.onSecondary,
                        ),
                        icon: const Icon(Icons.people_outline, size: 16),
                        label: const Text(
                          'Share (Guest)',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () {
                          _executeSharingCommand(
                            normalArgs: [
                              '-a',
                              widget.entry.path,
                              '-n',
                              shareName,
                              '-g',
                            ],
                            privilegeCommand:
                                'sharing -a \\"${widget.entry.path}\\" -n \\"$shareName\\" -g',
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 20),

                Text(
                  'Or copy Terminal Command to Share (macOS):',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          cliCommandSecure,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: cliCommandSecure),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Password protected command copied',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Alternatively, enable "File Sharing" in System Settings > Sharing, and add this folder.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                // Stop Share action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Stop Sharing Now'),
                    onPressed: () {
                      _executeSharingCommand(
                        normalArgs: ['-r', shareName],
                        privilegeCommand: 'sharing -r \\"$shareName\\"',
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 20),

                Text(
                  'Or copy Terminal Command to Stop Sharing (macOS):',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          stopCliCommand,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: stopCliCommand),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Remove command copied to clipboard',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUrlCard({
    required String title,
    required String url,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  url,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$title copied to clipboard')),
              );
            },
          ),
        ],
      ),
    );
  }
}
