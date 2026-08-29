import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart' as audioplayers;
import 'package:filesize/filesize.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';

import 'package:go_router/go_router.dart';
import '../../core/persistence/app_preferences.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/storage/models/transfer_progress.dart';
import '../../core/storage/models/connection_profile.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/storage/storage_provider_service.dart';
import '../../core/theme/glass_container.dart';
import '../connections/connections_sidebar.dart';
import '../connections/connection_repository.dart';
import '../file_operations/archive_service.dart';
import '../file_operations/file_operations_service.dart';
import '../file_operations/file_operations_state.dart';
import '../file_operations/operation_completion_sound_policy.dart';
import 'file_operations_actions.dart';
import 'file_panel.dart';
import 'panel_layout.dart';
import 'panel_controller.dart';

// Panel split ratio provider
final panelSplitRatioProvider =
    StateNotifierProvider<_PanelSplitRatioNotifier, double>(
      (ref) => _PanelSplitRatioNotifier(),
    );

class _PanelSplitRatioNotifier extends StateNotifier<double> {
  static const _key = 'panel_split_ratio';

  _PanelSplitRatioNotifier() : super(0.5) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.getInstance();
    state = (prefs.getDouble(_key) ?? 0.5).clamp(0.2, 0.8);
  }

  Future<void> set(double ratio) async {
    state = ratio.clamp(0.2, 0.8);
    final prefs = await AppPreferences.getInstance();
    await prefs.setDouble(_key, state);
  }
}

// Shell

class DualPaneShell extends ConsumerStatefulWidget {
  const DualPaneShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DualPaneShell> createState() => _DualPaneShellState();
}

class _DualPaneShellState extends ConsumerState<DualPaneShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(panelWorkspaceProvider.notifier).restorePanelCount();
      } catch (error) {
        debugPrint('Panel count could not be restored: $error');
      }
      if (!mounted) return;
      await ref.read(panelControllerProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final activeSide = ref.watch(activePanelProvider);
    final progress = ref.watch(operationProgressProvider);
    final clipboard = ref.watch(fileClipboardProvider);

    ref.listen<TransferProgress?>(operationProgressProvider, (previous, next) {
      if (OperationCompletionSoundPolicy.shouldPlay(
        enabled: ref.read(settingsProvider).playAnimationSounds,
        previous: previous,
        next: next,
      )) {
        final player = audioplayers.AudioPlayer();
        unawaited(player.play(audioplayers.AssetSource('sounds/success.wav')));
        player.onPlayerComplete.listen((_) => player.dispose());
      }
    });

    // The FlyingFileAnimation is now triggered directly inside FileOperationsActions.

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.f5): const CopyIntent(),
        const SingleActivator(LogicalKeyboardKey.f6): const MoveIntent(),
        const SingleActivator(LogicalKeyboardKey.f8): const DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const DeleteIntent(),
        const SingleActivator(LogicalKeyboardKey.tab):
            const SwitchPanelIntent(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const NewFolderIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const SelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            const CopyClipboardIntent(),
        const SingleActivator(LogicalKeyboardKey.keyX, control: true):
            const CutClipboardIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const PasteClipboardIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            const RefreshIntent(),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true):
            const ToggleHiddenIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopyIntent: CallbackAction<CopyIntent>(
            onInvoke: (_) {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .copyToOtherPanel(context, activeSide);
              return null;
            },
          ),
          MoveIntent: CallbackAction<MoveIntent>(
            onInvoke: (_) {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .moveToOtherPanel(context, activeSide);
              return null;
            },
          ),
          DeleteIntent: CallbackAction<DeleteIntent>(
            onInvoke: (_) {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .deleteSelected(context, activeSide);
              return null;
            },
          ),
          SwitchPanelIntent: CallbackAction<SwitchPanelIntent>(
            onInvoke: (_) {
              final workspace = ref.read(panelWorkspaceProvider);
              final activeIndex = workspace.panelOrder.indexOf(
                workspace.activePanelId,
              );
              final nextIndex = (activeIndex + 1) % workspace.panelOrder.length;
              ref
                  .read(panelWorkspaceProvider.notifier)
                  .setActive(workspace.panelOrder[nextIndex]);
              return null;
            },
          ),
          NewFolderIntent: CallbackAction<NewFolderIntent>(
            onInvoke: (_) {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .showNewFolderDialog(context, activeSide);
              return null;
            },
          ),
          SelectAllIntent: CallbackAction<SelectAllIntent>(
            onInvoke: (_) {
              ref.read(panelWorkspaceProvider.notifier).selectAll(activeSide);
              return null;
            },
          ),
          CopyClipboardIntent: CallbackAction<CopyClipboardIntent>(
            onInvoke: (_) {
              final state = ref.read(panelStateProvider(activeSide));
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .copyToClipboard(activeSide, state.activeTab.selectedEntries);
              return null;
            },
          ),
          CutClipboardIntent: CallbackAction<CutClipboardIntent>(
            onInvoke: (_) {
              final state = ref.read(panelStateProvider(activeSide));
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .cutToClipboard(activeSide, state.activeTab.selectedEntries);
              return null;
            },
          ),
          PasteClipboardIntent: CallbackAction<PasteClipboardIntent>(
            onInvoke: (_) {
              ref
                  .read(fileOperationsActionsProvider.notifier)
                  .paste(context, activeSide);
              return null;
            },
          ),
          RefreshIntent: CallbackAction<RefreshIntent>(
            onInvoke: (_) {
              unawaited(
                ref.read(panelControllerProvider.notifier).refresh(activeSide),
              );
              return null;
            },
          ),
          ToggleHiddenIntent: CallbackAction<ToggleHiddenIntent>(
            onInvoke: (_) {
              ref
                  .read(panelWorkspaceProvider.notifier)
                  .toggleHidden(activeSide);
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Wallpaper background
              _buildWallpaper(context),
              // Main content
              Column(
                children: [
                  _buildTopBar(context, l10n, activeSide),
                  Expanded(
                    child: Row(
                      children: [
                        const ConnectionsSidebar(),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    4,
                                    4,
                                    1,
                                  ),
                                  child:
                                      (GoRouterState.of(context).uri.path ==
                                              '/' ||
                                          GoRouterState.of(
                                            context,
                                          ).uri.path.startsWith('/connections'))
                                      ? _ResizablePanels()
                                      : widget.child,
                                ),
                              ),
                              _buildFunctionBar(
                                context,
                                l10n,
                                activeSide,
                                clipboard,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (progress != null) _buildProgressBar(context, progress),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the wallpaper background with a full-screen frosted-glass overlay.
  Widget _buildWallpaper(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final bgPath = settings.backgroundImagePath;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (bgPath == null) {
      // No wallpaper; use the normal Scaffold background colour.
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen wallpaper image
        Image.file(
          File(bgPath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        // Semi-transparent overlay so UI text stays readable
        Container(
          color: (isDark ? Colors.black : Colors.white).withValues(
            alpha: settings.backgroundOpacity,
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    gen.AppLocalizations l10n,
    PanelId activeSide,
  ) {
    final theme = Theme.of(context);
    final leftState = ref.watch(panelStateProvider(PanelId.a));
    final rightState = ref.watch(panelStateProvider(PanelId.b));

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? const Color(0xBB1C1C1E)
                : const Color(0xBBF5F5F7),
            border: Border(
              bottom: BorderSide(
                color: theme.brightness == Brightness.dark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x18000000),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.appTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  l10n.panelNumber(
                    ref
                            .watch(panelWorkspaceProvider)
                            .panelOrder
                            .indexOf(activeSide) +
                        1,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // TopBar is simplified. Path and Drive bars are inside panels.
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMountedDriveShortcuts(
    BuildContext context,
    ThemeData theme,
    PanelId activeSide,
  ) {
    final registry = ref.watch(storageProviderRegistryProvider);
    final connections = ref.watch(connectionRepositoryProvider);

    final activeMounts = <_MountItem>[];

    activeMounts.add(
      _MountItem(
        id: 'local',
        name: 'Local',
        icon: Icons.computer_outlined,
        color: theme.colorScheme.primary,
        onTap: () {
          ref
              .read(panelControllerProvider.notifier)
              .navigate(activeSide, '/', providerId: 'local');
        },
      ),
    );

    for (final profile in connections) {
      final provider = registry[profile.id];
      if (provider != null && provider.isConnected) {
        activeMounts.add(
          _MountItem(
            id: profile.id,
            name: profile.name,
            icon: _getIconForType(profile.type),
            color: _getColorForType(profile.type, theme),
            onTap: () async {
              try {
                final homePath = await provider.homePath;
                if (!context.mounted) return;
                await ref
                    .read(panelControllerProvider.notifier)
                    .navigate(activeSide, homePath, providerId: profile.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cannot open connection: $e')),
                  );
                }
              }
            },
          ),
        );
      }
    }

    if (activeMounts.isEmpty) return const SizedBox.shrink();

    final activeState = ref.watch(panelStateProvider(activeSide));
    final currentProviderId = activeState.activeTab.providerId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0x18FFFFFF)
            : const Color(0x0A000000),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? const Color(0x10FFFFFF)
              : const Color(0x08000000),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: activeMounts.map((mount) {
          final isSelected = mount.id == currentProviderId;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: mount.name,
              child: Material(
                color: isSelected
                    ? (theme.brightness == Brightness.dark
                          ? const Color(0x24FFFFFF)
                          : const Color(0x18000000))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: mount.onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mount.icon,
                          size: 16,
                          color: isSelected
                              ? mount.color
                              : mount.color.withValues(alpha: 0.65),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mount.name.length > 10
                              ? '${mount.name.substring(0, 8)}..'
                              : mount.name,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: isSelected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.65,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getIconForType(ConnectionType type) {
    return switch (type) {
      ConnectionType.sftp => Icons.terminal,
      ConnectionType.ftp => Icons.folder_shared,
      ConnectionType.ftps => Icons.folder_shared,
      ConnectionType.webdav => Icons.cloud,
      ConnectionType.smb => Icons.computer,
      ConnectionType.gdrive => Icons.cloud_upload,
      ConnectionType.dropbox => Icons.cloud_queue,
      ConnectionType.onedrive => Icons.cloud_circle,
      ConnectionType.nextcloud => Icons.cloud_sync,
      ConnectionType.local => Icons.computer_outlined,
    };
  }

  Color _getColorForType(ConnectionType type, ThemeData theme) {
    return switch (type) {
      ConnectionType.sftp => Colors.green,
      ConnectionType.ftp => Colors.orange,
      ConnectionType.ftps => Colors.deepOrange,
      ConnectionType.webdav => Colors.blue,
      ConnectionType.smb => Colors.purple,
      ConnectionType.gdrive => Colors.red,
      ConnectionType.dropbox => Colors.indigo,
      ConnectionType.onedrive => Colors.blueAccent,
      ConnectionType.nextcloud => Colors.lightBlue,
      ConnectionType.local => theme.colorScheme.primary,
    };
  }

  Widget _buildFunctionBar(
    BuildContext context,
    gen.AppLocalizations l10n,
    PanelId activeSide,
    ClipboardState? clipboard,
  ) {
    final theme = Theme.of(context);
    final actions = ref.read(fileOperationsActionsProvider.notifier);
    final activeState = ref.watch(panelStateProvider(activeSide));
    final hasSelection = activeState.activeTab.hasSelection;

    Widget actionButton({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      Color? color,
    }) {
      return _UiverseActionButton(
        icon: icon,
        label: label,
        onPressed: onPressed,
        color: color,
        theme: theme,
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(
        4.0,
        1.0,
        4.0,
        14.0,
      ), // 1px space from panel, 5mm from bottom edge, aligned with panels on left/right
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? const Color(0x991C1C1E)
                  : const Color(0x99F5F5F7),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.brightness == Brightness.dark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x18000000),
                width: 0.5,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  actionButton(
                    icon: Icons.create_new_folder_outlined,
                    label: l10n.actionNewFolder,
                    onPressed: () =>
                        actions.showNewFolderDialog(context, activeSide),
                  ),
                  const SizedBox(width: 2),
                  actionButton(
                    icon: Icons.copy_outlined,
                    label: 'F5 ${l10n.actionCopy}',
                    onPressed: hasSelection
                        ? () => actions.copyToOtherPanel(context, activeSide)
                        : null,
                  ),
                  const SizedBox(width: 2),
                  actionButton(
                    icon: Icons.drive_file_move_outline,
                    label: 'F6 ${l10n.actionMove}',
                    onPressed: hasSelection
                        ? () => actions.moveToOtherPanel(context, activeSide)
                        : null,
                  ),
                  const SizedBox(width: 2),
                  actionButton(
                    icon: Icons.edit_outlined,
                    label: l10n.actionRename,
                    onPressed:
                        hasSelection &&
                            activeState.activeTab.selectionCount == 1
                        ? () => actions.showRenameDialog(
                            context,
                            activeSide,
                            activeState.activeTab.selectedEntries.first,
                          )
                        : null,
                  ),
                  const SizedBox(width: 2),
                  actionButton(
                    icon: Icons.delete_outline,
                    label: 'F8 ${l10n.actionDelete}',
                    onPressed: hasSelection
                        ? () => actions.showDeleteDialog(
                            context,
                            activeSide,
                            activeState.activeTab.selectedEntries,
                          )
                        : null,
                    color: hasSelection
                        ? Colors.red.withValues(alpha: 0.8)
                        : null,
                  ),
                  actionButton(
                    icon: Icons.content_paste,
                    label: l10n.actionPaste,
                    onPressed:
                        clipboard == null || clipboard.sourcePaths.isEmpty
                        ? null
                        : () => actions.paste(context, activeSide),
                  ),
                  const SizedBox(width: 2),
                  actionButton(
                    icon: Icons.sync,
                    label: 'Sync',
                    onPressed: () => actions.syncPanels(context, activeSide),
                  ),
                  const SizedBox(width: 16),
                  if (!(clipboard == null)) ...[
                    Icon(
                      Icons.paste,
                      size: 12,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${clipboard.sourcePaths.length} ${clipboard.operation == ClipboardOperation.copy ? l10n.actionCopy : l10n.actionMove}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, TransferProgress progress) {
    if (progress.isFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 2), () {
          ref.read(operationProgressProvider.notifier).clear();
        });
      });
    }

    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isTransfer =
        progress.operation == TransferOperation.copy ||
        progress.operation == TransferOperation.move ||
        progress.operation == TransferOperation.delete ||
        progress.operation == TransferOperation.sync;
    final overallValue = progress.overallFraction ?? progress.fileFraction;
    final overallPercent = overallValue == null
        ? null
        : (overallValue * 100).round();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutQuart,
      margin: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xDD1C1C1E)
            : const Color(0xDDF5F5F7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (progress.state == TransferState.inProgress)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  (progress.operation ==
                                          TransferOperation.zip ||
                                      progress.operation ==
                                          TransferOperation.unzip)
                                  ? Colors.orange
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          Icon(
                            progress.operation == TransferOperation.copy
                                ? Icons.copy
                                : progress.operation == TransferOperation.move
                                ? Icons.drive_file_move
                                : progress.operation == TransferOperation.zip
                                ? Icons.folder_zip_outlined
                                : progress.operation == TransferOperation.unzip
                                ? Icons.unarchive_outlined
                                : Icons.sync,
                            size: 12,
                            color:
                                (progress.operation == TransferOperation.zip ||
                                    progress.operation ==
                                        TransferOperation.unzip)
                                ? Colors.orange
                                : theme.colorScheme.primary,
                          ),
                        ],
                      )
                    else if (progress.state == TransferState.completed)
                      Icon(
                        Icons.check_circle,
                        size: 24,
                        color: Colors.green.shade400,
                      )
                    else if (progress.state == TransferState.failed)
                      Icon(
                        Icons.error,
                        size: 24,
                        color: theme.colorScheme.error,
                      )
                    else if (progress.state == TransferState.cancelled)
                      Icon(
                        Icons.cancel,
                        size: 24,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (progress.operation) {
                              TransferOperation.copy => l10n.operationCopying(
                                progress.totalFiles,
                              ),
                              TransferOperation.move => l10n.operationMoving(
                                progress.totalFiles,
                              ),
                              TransferOperation.delete =>
                                l10n.operationDeleting(progress.totalFiles),
                              TransferOperation.zip =>
                                '${progress.filesTransferred}/${progress.totalFiles} öğe sıkıştırılıyor...',
                              TransferOperation.unzip =>
                                '${progress.filesTransferred} öğe arşivden çıkarılıyor...',
                              TransferOperation.sync =>
                                'Senkronize ediliyor...',
                              TransferOperation.read => 'Okunuyor...',
                              TransferOperation.write => 'Yazılıyor...',
                            },
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color:
                                  (progress.operation ==
                                          TransferOperation.zip ||
                                      progress.operation ==
                                          TransferOperation.unzip)
                                  ? Colors.orange
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            progress.currentFile?.name ?? 'Processing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (overallPercent != null) ...[
                      const SizedBox(width: 16),
                      Text(
                        '$overallPercent%',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (progress.state == TransferState.inProgress) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: l10n.actionCancel,
                        onPressed: () {
                          ref
                              .read(archiveServiceProvider.notifier)
                              .cancelCurrentOperation();
                          ref
                              .read(fileOperationsServiceProvider.notifier)
                              .cancelOperation();
                        },
                      ),
                    ],
                  ],
                ),
                if (isTransfer) ...[
                  const SizedBox(height: 14),
                  _buildProgressStage(
                    context: context,
                    title: l10n.progressCurrentFile,
                    details:
                        '${filesize(progress.bytesTransferred)} / '
                        '${filesize(progress.totalBytes)} • '
                        '${l10n.progressRemaining(filesize(progress.currentFileRemainingBytes))}',
                    value: progress.currentFileFraction,
                    color: const Color(0xFF22C7C9),
                  ),
                  const SizedBox(height: 12),
                  _buildProgressStage(
                    context: context,
                    title: l10n.progressOverall,
                    details:
                        '${filesize(progress.overallBytesTransferred)} / '
                        '${filesize(progress.overallTotalBytes)} • '
                        '${l10n.progressRemaining(filesize(progress.overallRemainingBytes))}',
                    value: overallValue,
                    color: theme.colorScheme.primary,
                  ),
                  if (progress.state == TransferState.inProgress) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.speed,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          l10n.progressSpeed(filesize(progress.speed.round())),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          progress.estimatedRemaining == null
                              ? l10n.progressEtaCalculating
                              : l10n.progressEta(
                                  _formatEta(progress.estimatedRemaining!),
                                ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (progress.fraction != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStage({
    required BuildContext context,
    required String title,
    required String details,
    required double? value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  String _formatEta(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _shortenPath(String path, int maxLen) {
    if (path.length <= maxLen) return path;
    final parts = path.split('/');
    if (parts.length <= 2) return path;
    return '${parts[0]}/.../${parts.last}';
  }
}

// Resizable dual panel

class _ResizablePanels extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ResizablePanels> createState() => _ResizablePanelsState();
}

class _ResizablePanelsState extends ConsumerState<_ResizablePanels> {
  bool _isDragging = false;

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final totalWidth = constraints.maxWidth - _kDividerWidth;
    final delta = details.delta.dx / totalWidth;
    final current = ref.read(panelSplitRatioProvider);
    ref.read(panelSplitRatioProvider.notifier).set(current + delta);
  }

  @override
  Widget build(BuildContext context) {
    final ratio = ref.watch(panelSplitRatioProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);
    final workspace = ref.watch(panelWorkspaceProvider);

    if (settings.singlePanelMode) {
      final activeSide = ref.watch(activePanelProvider);
      return FilePanel(
        key: ValueKey('file-panel-${activeSide.value}'),
        side: activeSide,
      );
    }

    final panelOrder = workspace.panelOrder;
    if (panelOrder.length > 2) {
      return _buildPanelGrid(theme, panelOrder);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - _kDividerWidth;
        final leftWidth = available * ratio;
        final rightWidth = available * (1 - ratio);

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: FilePanel(
                key: ValueKey('file-panel-${panelOrder.first.value}'),
                side: panelOrder.first,
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) =>
                    setState(() => _isDragging = true),
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, constraints),
                onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _kDividerWidth,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : (isDark
                              ? const Color(0x22FFFFFF)
                              : const Color(0x18000000)),
                  ),
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _isDragging ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth,
              child: FilePanel(
                key: ValueKey('file-panel-${panelOrder.last.value}'),
                side: panelOrder.last,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPanelGrid(ThemeData theme, List<PanelId> panelOrder) {
    final layout = PanelLayoutSpec.forPanels(panelOrder);
    final rows = <Widget>[];

    for (var rowIndex = 0; rowIndex < layout.rows.length; rowIndex++) {
      if (rowIndex > 0) {
        rows.add(_gridDivider(theme, Axis.horizontal));
      }

      final panels = <Widget>[];
      for (
        var panelIndex = 0;
        panelIndex < layout.rows[rowIndex].length;
        panelIndex++
      ) {
        if (panelIndex > 0) {
          panels.add(_gridDivider(theme, Axis.vertical));
        }
        final panelId = layout.rows[rowIndex][panelIndex];
        panels.add(
          Expanded(
            child: FilePanel(
              key: ValueKey('file-panel-${panelId.value}'),
              side: panelId,
            ),
          ),
        );
      }

      rows.add(Expanded(child: Row(children: panels)));
    }

    return Column(children: rows);
  }

  Widget _gridDivider(ThemeData theme, Axis axis) {
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: axis == Axis.vertical ? _kDividerWidth : null,
      height: axis == Axis.horizontal ? _kDividerWidth : null,
      child: ColoredBox(
        color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
      ),
    );
  }
}

const double _kDividerWidth = 4.0;

// ─── Path label ──────────────────────────────────────────────────────────────

class _PathLabel extends StatelessWidget {
  const _PathLabel({required this.path, required this.active});
  final String path;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        fontWeight: active ? FontWeight.w500 : FontWeight.w400,
        fontSize: 11,
      ),
      child: Text(path, overflow: TextOverflow.ellipsis),
    );
  }
}

class _FnDivider extends StatelessWidget {
  const _FnDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 0.5,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: isDark ? const Color(0x33FFFFFF) : const Color(0x25000000),
    );
  }
}

// ─── Mount item model ────────────────────────────────────────────────────────

class _MountItem {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MountItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

// ─── Intent classes for keyboard shortcuts ───────────────────────

class CopyIntent extends Intent {
  const CopyIntent();
}

class MoveIntent extends Intent {
  const MoveIntent();
}

class DeleteIntent extends Intent {
  const DeleteIntent();
}

class SwitchPanelIntent extends Intent {
  const SwitchPanelIntent();
}

class NewFolderIntent extends Intent {
  const NewFolderIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class CopyClipboardIntent extends Intent {
  const CopyClipboardIntent();
}

class CutClipboardIntent extends Intent {
  const CutClipboardIntent();
}

class PasteClipboardIntent extends Intent {
  const PasteClipboardIntent();
}

class RefreshIntent extends Intent {
  const RefreshIntent();
}

class ToggleHiddenIntent extends Intent {
  const ToggleHiddenIntent();
}

class _UiverseActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final ThemeData theme;

  const _UiverseActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    required this.theme,
  });

  @override
  State<_UiverseActionButton> createState() => _UiverseActionButtonState();
}

class _UiverseActionButtonState extends State<_UiverseActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onPressed != null;
    final isDark = widget.theme.brightness == Brightness.dark;
    final turquoise = isDark
        ? const Color(0xFF00E5FF)
        : const Color(0xFF00838F);
    final btnColor = widget.color ?? turquoise;

    // Default (not hovered) backgrounds: light mode = white, dark mode = black
    final defaultBgColor = isDark ? Colors.black : Colors.white;

    // Hover durumunda doluluk rengi turkuaz, değilse tema rengidir.
    final bgColor = active
        ? (_isHovered ? btnColor : defaultBgColor)
        : Colors.transparent;

    // Hover durumunda yazı ve ikon zıt renge döner, değilse turkuaz kalır.
    final contentColor = active
        ? (_isHovered ? (isDark ? Colors.black : Colors.white) : btnColor)
        : widget.theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) {
          if (active) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (active) setState(() => _isHovered = false);
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: active
                      ? btnColor
                      : widget.theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.2,
                        ),
                  width: 2.0,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF0A192F,
                          ).withValues(alpha: 0.4), // Koyu lacivert gölge
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hover durumunda ikonu sağa 4px kaydıran animasyon.
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(
                      left: _isHovered ? 4.0 : 0.0,
                      right: _isHovered ? 0.0 : 4.0,
                    ),
                    child: Icon(widget.icon, size: 13, color: contentColor),
                  ),
                  Text(
                    widget.label,
                    style: widget.theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: contentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
