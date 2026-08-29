import 'dart:async';
import 'dart:io';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/commands/command_context.dart';
import '../../core/commands/command_id.dart';
import '../../core/commands/command_result.dart';
import '../../core/storage/models/file_entry.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/theme/glass_container.dart';
import '../../core/storage/storage_provider_service.dart';
import '../../widgets/cascade_menu/cascade_menu.dart';
import '../../core/storage/models/transfer_progress.dart';
import '../../core/settings/recent_service.dart';
import '../file_operations/archive_service.dart';
import '../file_operations/file_operations_state.dart';
import '../file_operations/panel_drag_policy.dart';
import '../file_operations/file_open_service.dart';
import '../file_operations/file_operations_service.dart';
import '../context_menu/application/command_orchestrator.dart';
import '../context_menu/application/file_panel_command_registry.dart';
import '../context_menu/commands/command_action.dart';
import '../context_menu/presentation/file_panel_context_menu_builder.dart';
import '../shell_adaptive/panel_controller.dart';
import '../preview/quick_look_dialog.dart';
import '../../core/settings/settings_provider.dart';
import 'file_operations_actions.dart';
import 'panel_drive_bar.dart';
import 'panel_path_bar.dart';

import 'panel_tabs_bar.dart';

/// Data class for drag-and-drop between panels
class PanelDragData {
  final PanelId sourceSide;
  final List<FileEntry> entries;

  PanelDragData({required this.sourceSide, required this.entries});
}

/// A single file panel showing a directory listing with navigation,
/// selection, sorting, and context menu support.
class FilePanel extends ConsumerStatefulWidget {
  const FilePanel({required this.side, super.key});

  final PanelId side;

  @override
  ConsumerState<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends ConsumerState<FilePanel> {
  late ScrollController _scrollController;
  String? _lastSelectedPath;
  bool _showAddressBar = false;
  late TextEditingController _addressController;
  double _sizeColWidth = 72;
  double _dateColWidth = 110;
  late TextEditingController _searchController;

  String? _lastPath;
  final Map<String, int?> _calculatedSizes = {};

  String? _editingEntryPath;
  late TextEditingController _renameController;
  late FocusNode _renameFocusNode;
  late FocusNode _panelFocusNode;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _addressController = TextEditingController();
    _searchController = TextEditingController();
    _renameController = TextEditingController();
    _renameFocusNode = FocusNode();
    _panelFocusNode = FocusNode();

    _renameFocusNode.addListener(() {
      if (!_renameFocusNode.hasFocus && _editingEntryPath != null) {
        _commitRename();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    _renameController.dispose();
    _renameFocusNode.dispose();
    _panelFocusNode.dispose();
    super.dispose();
  }

  PanelState get _panelState => ref.watch(panelStateProvider(widget.side));

  bool get _isActive => ref.watch(activePanelProvider) == widget.side;

  PanelWorkspace get _panels => ref.read(panelWorkspaceProvider.notifier);

  PanelId get _otherPanelId => ref
      .read(panelWorkspaceProvider)
      .panelOrder
      .firstWhere((panelId) => panelId != widget.side);

  StorageProvider _providerForPanel(PanelId panelId) {
    final panel = ref.read(panelStateProvider(panelId));
    if (panel.activeTab.providerId == 'local') {
      return ref.read(localStorageProviderProvider);
    }
    return ref.read(
      storageProviderRegistryProvider,
    )[panel.activeTab.providerId]!;
  }

  void _selectPanel() {
    _panels.setActive(widget.side);
    if (!_panelFocusNode.hasFocus) {
      _panelFocusNode.requestFocus();
    }
  }

  void _onEntryTap(
    FileEntry entry, {
    bool isControlPressed = false,
    bool isShiftPressed = false,
  }) {
    _selectPanel();

    if (isShiftPressed && _lastSelectedPath != null) {
      // Range selection
      _panels.selectRange(widget.side, _lastSelectedPath!, entry.path);
    } else if (isControlPressed) {
      // Toggle selection
      _panels.toggleSelection(widget.side, entry.path);
      _lastSelectedPath = entry.path;
    } else {
      // Single selection
      final isCurrentlySelected = ref
          .read(panelStateProvider(widget.side))
          .activeTab
          .selectedPaths
          .contains(entry.path);

      if (isCurrentlySelected && _isActive && _editingEntryPath == null) {
        // Zaten seçiliyse ve panel aktifse, satır içi yeniden adlandırmayı başlat.
        _startInlineRename(entry);
      } else {
        _panels.selectEntry(widget.side, entry.path);
        _lastSelectedPath = entry.path;
        setState(() => _editingEntryPath = null);
      }
    }
  }

  void _onEntryDoubleTap(FileEntry entry) {
    if (_panelState.activeTab.searchQuery != null) {
      final targetSide = _otherPanelId;
      if (entry.isDirectory) {
        ref
            .read(panelControllerProvider.notifier)
            .navigate(targetSide, entry.path);
      } else {
        // Find parent directory using path package or basic string manipulation
        final lastSlash = entry.path.lastIndexOf('/');
        final parentPath = lastSlash > 0
            ? entry.path.substring(0, lastSlash)
            : '/';
        ref
            .read(panelControllerProvider.notifier)
            .navigate(targetSide, parentPath);

        // Wait briefly for navigate to load, then select it.
        // A more robust way would be to select it when navigation completes, but this is a quick attempt.
        Future.delayed(const Duration(milliseconds: 300), () {
          _panels.selectEntry(targetSide, entry.path);
        });
      }
    } else {
      if (entry.isDirectory) {
        ref
            .read(panelControllerProvider.notifier)
            .navigate(widget.side, entry.path);
      } else {
        final actions = ref.read(fileOperationsActionsProvider.notifier);
        actions.openWithDefault(context, widget.side, entry);
      }
    }
  }

  void _onEntrySecondaryTap(FileEntry entry, Offset position) {
    _selectPanel();

    if (!_panelState.activeTab.selectedPaths.contains(entry.path)) {
      _panels.selectEntry(widget.side, entry.path);
    }

    _showContextMenu(context, position, entry: entry);
  }

  void _onPanelSecondaryTap(TapUpDetails details) {
    _selectPanel();
    _showContextMenu(context, details.globalPosition);
  }

  void _startInlineRename(FileEntry entry) {
    setState(() {
      _editingEntryPath = entry.path;
      _renameController.text = entry.name;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) _renameFocusNode.requestFocus();
    });
  }

  Future<void> _commitRename() async {
    final path = _editingEntryPath;
    if (path == null) return;

    final entry = _panelState.activeTab.entries
        .where((e) => e.path == path)
        .firstOrNull;
    final newName = _renameController.text.trim();

    setState(() => _editingEntryPath = null);

    if (entry != null && newName.isNotEmpty && newName != entry.name) {
      final actions = ref.read(fileOperationsActionsProvider.notifier);
      final provider = _providerForPanel(widget.side);

      try {
        await ref
            .read(fileOperationsServiceProvider.notifier)
            .rename(provider: provider, entry: entry, newName: newName);
        await ref.read(panelControllerProvider.notifier).refresh(widget.side);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  Future<void> _calculateSizesForSelection(List<FileEntry> entries) async {
    final provider = _providerForPanel(widget.side);

    for (final entry in entries) {
      if (!entry.isDirectory) continue;

      setState(() {
        _calculatedSizes[entry.path] = null;
      });

      final size = await _computeFolderSize(provider, entry.path);

      if (mounted) {
        setState(() {
          if (_calculatedSizes.containsKey(entry.path)) {
            _calculatedSizes[entry.path] = size;
          }
        });
      }
    }
  }

  Future<int> _computeFolderSize(StorageProvider provider, String path) async {
    int total = 0;
    try {
      final entries = await provider.list(path);
      for (final entry in entries) {
        if (!entry.isDirectory) {
          total += entry.size;
        } else if (!entry.symlink) {
          total += await _computeFolderSize(provider, entry.path);
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _openInTerminal(String path) async {
    final provider = _providerForPanel(widget.side);
    final opened = await ref
        .read(fileOpenServiceProvider.notifier)
        .openInTerminal(path, provider: provider);
    if (!mounted || opened) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Terminal açılamadı. Bu seçenek yalnızca yerel klasörlerde çalışır.',
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position, {
    FileEntry? entry,
  }) {
    unawaited(_openContextMenu(context, position, entry: entry));
  }

  Future<void> _openContextMenu(
    BuildContext context,
    Offset position, {
    FileEntry? entry,
  }) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final actions = ref.read(fileOperationsActionsProvider.notifier);
    final clipboard = ref.read(fileClipboardProvider);
    final hasClipboardItems =
        clipboard != null && clipboard.sourcePaths.isNotEmpty;
    final editorName = preferredEditorName(currentFileOpenPlatform);
    final provider = _providerForPanel(widget.side);
    final canOpenInTerminal = supportsTerminalOpenForProvider(
      platform: currentFileOpenPlatform,
      provider: provider,
    );
    final selected = _panelState.activeTab.selectedEntries;
    final entries = entry == null
        ? selected
        : (selected.isEmpty ? <FileEntry>[entry] : selected);
    final commandContext = _createCommandContext(
      entry: entry,
      entries: entries,
      provider: provider,
      canOpenInTerminal: canOpenInTerminal,
      hasClipboardItems: hasClipboardItems,
    );
    final registry = buildFilePanelCommandRegistry(
      _filePanelCommandActions(context, actions),
    );
    final menu = FilePanelContextMenuBuilder(registry).build(
      FilePanelContextMenuInput(
        context: commandContext,
        labels: _contextMenuLabels(l10n),
        hasEntry: entry != null,
        entryIsDirectory: entry?.isDirectory ?? false,
        entryIsArchive: entry != null && actions.isArchiveFile(entry),
        entryIsShared: entry?.isShared ?? false,
        recentApplications: _recentApplicationMenuItems(),
        editorName: editorName,
      ),
    );

    final value = await showCascadeMenu(
      context: context,
      position: position,
      items: menu.items,
    );
    if (value == null || !mounted) return;
    final selection = menu.selections[value];
    if (selection == null) return;
    await CommandOrchestrator(registry: registry).dispatch(
      selection.commandId,
      commandContext.withArguments(selection.arguments),
    );
  }

  CommandContext _createCommandContext({
    required FileEntry? entry,
    required List<FileEntry> entries,
    required StorageProvider provider,
    required bool canOpenInTerminal,
    required bool hasClipboardItems,
  }) {
    final capabilities = <CommandCapability>{
      CommandCapability.read,
      CommandCapability.archive,
      CommandCapability.share,
      if (provider.supports(ProviderCapability.write)) CommandCapability.write,
      if (provider.supports(ProviderCapability.move)) CommandCapability.rename,
      if (provider.supports(ProviderCapability.delete))
        CommandCapability.delete,
      if (canOpenInTerminal) ...<CommandCapability>{
        CommandCapability.localPath,
        CommandCapability.terminal,
      },
    };
    return CommandContext(
      sourcePanelId: widget.side.value,
      providerId: _panelState.activeTab.providerId,
      currentPath: _panelState.activeTab.currentPath,
      clickedEntry: entry,
      selectedEntries: entries,
      targetPanelIds: ref
          .read(panelWorkspaceProvider)
          .panelOrder
          .where((panelId) => panelId != widget.side)
          .map((panelId) => panelId.value)
          .toList(growable: false),
      capabilities: capabilities,
      showHidden: _panelState.activeTab.showHidden,
      hasClipboardEntries: hasClipboardItems,
    );
  }

  FilePanelContextMenuLabels _contextMenuLabels(gen.AppLocalizations l10n) =>
      FilePanelContextMenuLabels(
        open: l10n.actionOpen,
        openDefault: l10n.actionOpenDefault,
        edit: l10n.actionEdit,
        openWith: l10n.actionOpenWith,
        chooseApplication: l10n.actionChooseApplication,
        quickLook: 'Önizle (Quick Look)',
        reveal: l10n.actionRevealInFinder,
        copyPath: 'Yolu Kopyala',
        copy: l10n.actionCopy,
        move: l10n.actionMove,
        paste: l10n.actionPaste,
        rename: l10n.actionRename,
        delete: l10n.actionDelete,
        compress: 'Sıkıştırma',
        compressZip: l10n.actionCompressZip,
        compressTar: l10n.actionCompressTar,
        compressTarGz: l10n.actionCompressTarGz,
        compressPasswordZip: 'Şifreli ZIP...',
        extract: l10n.actionExtract,
        fileParts: 'Parçala / Birleştir',
        splitFile: 'Parçala',
        mergeFileParts: 'Birleştir',
        shareSmb: 'SMB ile Paylaş',
        stopSharingSmb: 'SMB Paylaşımını Durdur / Düzenle',
        properties: l10n.actionProperties,
        newFolder: l10n.actionNewFolder,
        newFile: 'Yeni Dosya',
        showHidden: 'Gizli dosyaları göster',
        hideHidden: 'Gizli dosyaları gizle',
        openTerminal: 'Terminalde aç',
        equalizePanel: 'Diğer Paneli Eşitle (=)',
        selectAll: l10n.actionSelectAll,
        refresh: l10n.actionRefresh,
      );

  List<RecentApplicationMenuItem> _recentApplicationMenuItems() => ref
      .read(recentServiceProvider)
      .recentApps
      .map(
        (appPath) => RecentApplicationMenuItem(
          path: appPath,
          label: appPath
              .split(RegExp(r'[/\\]'))
              .last
              .replaceAll(RegExp(r'\.app$', caseSensitive: false), ''),
        ),
      )
      .toList(growable: false);

  Map<CommandId, CommandAction> _filePanelCommandActions(
    BuildContext uiContext,
    FileOperationsActions actions,
  ) => <CommandId, CommandAction>{
    ..._openCommandActions(uiContext, actions),
    ..._operationCommandActions(uiContext, actions),
    ..._backgroundCommandActions(uiContext, actions),
  };

  Map<CommandId, CommandAction> _openCommandActions(
    BuildContext uiContext,
    FileOperationsActions actions,
  ) => <CommandId, CommandAction>{
    CommandId.openEntry: (commandContext) async {
      _onEntryDoubleTap(commandContext.clickedEntry!);
      return const CommandResult.completed();
    },
    CommandId.openDefault: (commandContext) async {
      await actions.openWithDefault(
        uiContext,
        widget.side,
        commandContext.clickedEntry!,
      );
      return const CommandResult.completed();
    },
    CommandId.editFile: (commandContext) async {
      await actions.editFile(uiContext, commandContext.clickedEntry!);
      return const CommandResult.completed();
    },
    CommandId.openWith: (commandContext) async {
      final applicationPath = commandContext.argument<String>(
        'applicationPath',
      );
      if (applicationPath == null) {
        await actions.chooseAppAndOpen(uiContext, commandContext.clickedEntry!);
      } else {
        await actions.openWithApplication(
          uiContext,
          commandContext.clickedEntry!,
          applicationPath,
        );
      }
      return const CommandResult.completed();
    },
    CommandId.quickLook: (commandContext) async {
      await showDialog<void>(
        context: uiContext,
        builder: (dialogContext) => QuickLookDialog(
          entry: commandContext.clickedEntry!,
          providerId: commandContext.providerId,
        ),
      );
      return const CommandResult.completed();
    },
    CommandId.reveal: (commandContext) async {
      await actions.revealInFileManager(
        uiContext,
        commandContext.clickedEntry!,
      );
      return const CommandResult.completed();
    },
    CommandId.copyPath: (commandContext) async {
      await _copyPathToClipboard(uiContext, commandContext.clickedEntry!.path);
      return const CommandResult.completed();
    },
    CommandId.openTerminal: (commandContext) async {
      await _openInTerminal(commandContext.clickedEntry!.path);
      return const CommandResult.completed();
    },
    CommandId.shareSmb: (commandContext) async {
      await actions.showShareSmbDialog(uiContext, commandContext.clickedEntry!);
      return const CommandResult.completed();
    },
    CommandId.properties: (commandContext) async {
      final selectedEntry = commandContext.clickedEntry!;
      if (selectedEntry.isDirectory) {
        _showFolderPropertiesDialog(uiContext, selectedEntry);
      } else {
        await actions.showPropertiesDialog(uiContext, selectedEntry);
      }
      return const CommandResult.completed();
    },
  };

  Map<CommandId, CommandAction> _operationCommandActions(
    BuildContext uiContext,
    FileOperationsActions actions,
  ) => <CommandId, CommandAction>{
    CommandId.copySelection: (commandContext) async {
      actions.copyToClipboard(widget.side, commandContext.effectiveEntries);
      return const CommandResult.completed();
    },
    CommandId.moveSelection: (commandContext) async {
      actions.cutToClipboard(widget.side, commandContext.effectiveEntries);
      return const CommandResult.completed();
    },
    CommandId.paste: (commandContext) async {
      await actions.paste(uiContext, widget.side);
      return const CommandResult.completed();
    },
    CommandId.rename: (commandContext) async {
      _startInlineRename(commandContext.effectiveEntries.single);
      return const CommandResult.completed();
    },
    CommandId.delete: (commandContext) async {
      await actions.showDeleteDialog(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
      );
      return const CommandResult.completed();
    },
    CommandId.compressZip: (commandContext) async {
      await actions.compressEntries(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
        ArchiveFormat.zip,
      );
      return const CommandResult.completed();
    },
    CommandId.compressTar: (commandContext) async {
      await actions.compressEntries(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
        ArchiveFormat.tar,
      );
      return const CommandResult.completed();
    },
    CommandId.compressTarGz: (commandContext) async {
      await actions.compressEntries(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
        ArchiveFormat.tarGz,
      );
      return const CommandResult.completed();
    },
    CommandId.compressPasswordZip: (commandContext) async {
      await actions.compressEntriesWithPassword(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
      );
      return const CommandResult.completed();
    },
    CommandId.extract: (commandContext) async {
      await actions.extractArchive(
        uiContext,
        widget.side,
        commandContext.clickedEntry!,
      );
      return const CommandResult.completed();
    },
    CommandId.splitFile: (commandContext) async {
      await actions.splitFile(
        uiContext,
        widget.side,
        commandContext.effectiveEntries.single,
      );
      return const CommandResult.completed();
    },
    CommandId.mergeFileParts: (commandContext) async {
      await actions.mergeFileParts(
        uiContext,
        widget.side,
        commandContext.effectiveEntries,
      );
      return const CommandResult.completed();
    },
  };

  Map<CommandId, CommandAction> _backgroundCommandActions(
    BuildContext uiContext,
    FileOperationsActions actions,
  ) => <CommandId, CommandAction>{
    CommandId.createFolder: (commandContext) async {
      await actions.showNewFolderDialog(uiContext, widget.side);
      return const CommandResult.completed();
    },
    CommandId.createFile: (commandContext) async {
      await actions.showNewFileDialog(uiContext, widget.side);
      return const CommandResult.completed();
    },
    CommandId.toggleHidden: (commandContext) async {
      _panels.toggleHidden(widget.side);
      return const CommandResult.completed();
    },
    CommandId.openTerminalHere: (commandContext) async {
      await _openInTerminal(commandContext.currentPath);
      return const CommandResult.completed();
    },
    CommandId.revealCurrentFolder: (commandContext) async {
      await ref
          .read(fileOpenServiceProvider.notifier)
          .revealInFileManager(commandContext.currentPath);
      return const CommandResult.completed();
    },
    CommandId.copyCurrentPath: (commandContext) async {
      await _copyPathToClipboard(uiContext, commandContext.currentPath);
      return const CommandResult.completed();
    },
    CommandId.equalizePanelPath: (commandContext) async {
      await ref
          .read(panelControllerProvider.notifier)
          .navigate(
            _otherPanelId,
            commandContext.currentPath,
            providerId: commandContext.providerId,
          );
      return const CommandResult.completed();
    },
    CommandId.selectAll: (commandContext) async {
      _panels.selectAll(widget.side);
      return const CommandResult.completed();
    },
    CommandId.refresh: (commandContext) async {
      await ref.read(panelControllerProvider.notifier).refresh(widget.side);
      return const CommandResult.completed();
    },
  };

  Future<void> _copyPathToClipboard(BuildContext uiContext, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!uiContext.mounted) return;
    ScaffoldMessenger.of(
      uiContext,
    ).showSnackBar(const SnackBar(content: Text('Yol panoya kopyalandı')));
  }

  void _navigateToAddress() {
    final path = _addressController.text.trim();
    if (path.isNotEmpty) {
      ref.read(panelControllerProvider.notifier).navigate(widget.side, path);
    }
    setState(() => _showAddressBar = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final state = _panelState;
    if (_lastPath != state.activeTab.currentPath) {
      _calculatedSizes.clear();
      _lastPath = state.activeTab.currentPath;
    }

    final isActive = _isActive;
    final theme = Theme.of(context);
    final panelOrder = ref.watch(
      panelWorkspaceProvider.select((workspace) => workspace.panelOrder),
    );
    final canAddPanel = ref.watch(
      panelWorkspaceProvider.select((workspace) => workspace.canAddPanel),
    );
    final panelIndex = panelOrder.indexOf(widget.side);
    final canRemovePanel =
        panelOrder.length > PanelWorkspaceState.minPanelCount;

    return Focus(
      focusNode: _panelFocusNode,
      autofocus: isActive,
      onFocusChange: (hasFocus) {
        if (hasFocus) _selectPanel();
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyT) {
            final isMac = Theme.of(context).platform == TargetPlatform.macOS;
            final hasModifier = isMac
                ? (HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.metaLeft,
                      ) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.metaRight,
                      ) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.altLeft,
                      ) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.altRight,
                      ))
                : (HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.altLeft,
                      ) ||
                      HardwareKeyboard.instance.logicalKeysPressed.contains(
                        LogicalKeyboardKey.altRight,
                      ));

            if (hasModifier) {
              final currentPath = _panelState.activeTab.currentPath;
              _panels.addTab(widget.side, currentPath);
              return KeyEventResult.handled;
            }
          }
        }

        if (event.logicalKey == LogicalKeyboardKey.space) {
          if (state.activeTab.hasSelection) {
            if (event is KeyDownEvent) {
              final firstSelected = state.activeTab.selectedEntries.first;
              showDialog(
                context: context,
                builder: (context) => QuickLookDialog(
                  entry: firstSelected,
                  providerId: state.activeTab.providerId,
                ),
              );
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _selectPanel();
          setState(() => _editingEntryPath = null);
          // Click on empty area = clear selection
          _panels.clearSelection(widget.side);
        },
        onSecondaryTapUp: _onPanelSecondaryTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: isActive ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: isActive
                ? (ref.watch(settingsProvider).backgroundImagePath != null
                      ? theme.colorScheme.surface.withValues(alpha: 0.5)
                      : theme.colorScheme.primary.withValues(alpha: 0.08))
                : (ref.watch(settingsProvider).backgroundImagePath != null
                      ? theme.colorScheme.surface.withValues(alpha: 0.25)
                      : theme.colorScheme.surfaceContainerLow.withValues(
                          alpha: 0.3,
                        )),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                _buildPanelHeader(
                  context,
                  l10n,
                  panelIndex: panelIndex,
                  canAddPanel: canAddPanel,
                  canRemovePanel: canRemovePanel,
                  sourcePath: state.activeTab.currentPath,
                  sourceProviderId: state.activeTab.providerId,
                ),
                PanelDriveBar(side: widget.side),
                PanelTabsBar(side: widget.side),
                PanelPathBar(side: widget.side),
                if (state.activeTab.error != null)
                  _buildErrorBar(context, state.activeTab.error!),
                _buildColumnHeader(context, l10n, state),
                Expanded(
                  child: state.activeTab.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.activeTab.entries.isEmpty
                      ? _buildEmptyState(context, l10n)
                      : _buildFileList(context, l10n, state),
                ),
                _buildStatusBar(context, l10n, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelHeader(
    BuildContext context,
    gen.AppLocalizations l10n, {
    required int panelIndex,
    required bool canAddPanel,
    required bool canRemovePanel,
    required String sourcePath,
    required String sourceProviderId,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 2),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(
            Icons.view_agenda_outlined,
            size: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            l10n.panelNumber(panelIndex + 1),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            key: ValueKey('panel-add-${widget.side.value}'),
            tooltip: l10n.panelAdd,
            onPressed: canAddPanel
                ? () => _panels.addPanel(
                    path: sourcePath,
                    providerId: sourceProviderId,
                  )
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded),
          ),
          const Spacer(),
          if (canRemovePanel)
            IconButton(
              key: ValueKey('panel-close-${widget.side.value}'),
              tooltip: l10n.panelClose,
              onPressed: () => _panels.removePanel(widget.side),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader(
    BuildContext context,
    gen.AppLocalizations l10n,
    PanelState state,
  ) {
    final theme = Theme.of(context);
    final sortColor = theme.colorScheme.primary;

    Widget headerCell(
      String label,
      SortField field, {
      bool alignRight = false,
    }) {
      final isSorted = state.activeTab.sortField == field;
      return InkWell(
        onTap: () {
          _panels.toggleSort(widget.side, field);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSorted
                        ? sortColor
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 2),
                Icon(
                  state.activeTab.sortDirection == SortDirection.ascending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 12,
                  color: sortColor,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final showSize = w > 160;
          final showDate = w > 260;
          return Row(
            children: [
              // Name column - always visible
              Expanded(
                flex: 1,
                child: headerCell(l10n.sortByName, SortField.name),
              ),

              if (showSize)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  hitTestBehavior: HitTestBehavior.translucent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _sizeColWidth = (_sizeColWidth - details.delta.dx)
                            .clamp(50.0, 300.0);
                      });
                    },
                    child: Container(
                      width: 12,
                      height: 24,
                      alignment: Alignment.center,
                      child: Container(
                        width: 1,
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),

              // Size column - only when wide enough
              if (showSize)
                SizedBox(
                  width: _sizeColWidth,
                  child: headerCell(
                    l10n.sortBySize,
                    SortField.size,
                    alignRight: true,
                  ),
                ),

              if (showDate)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  hitTestBehavior: HitTestBehavior.translucent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _dateColWidth = (_dateColWidth - details.delta.dx)
                            .clamp(80.0, 300.0);
                      });
                    },
                    child: Container(
                      width: 12,
                      height: 24,
                      alignment: Alignment.center,
                      child: Container(
                        width: 1,
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),

              // Date column - only when wide enough
              if (showDate)
                SizedBox(
                  width: _dateColWidth,
                  child: headerCell(
                    l10n.sortByDate,
                    SortField.date,
                    alignRight: true,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorBar(BuildContext context, String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              _panels.setError(widget.side, null);
            },
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, gen.AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.emptyFolder,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(
    BuildContext context,
    gen.AppLocalizations l10n,
    PanelState state,
  ) {
    return DragTarget<PanelDragData>(
      onWillAcceptWithDetails: (details) {
        return PanelDragPolicy.resolveTarget(
              sourcePanelId: details.data.sourceSide,
              targetPanelId: widget.side,
              entryCount: details.data.entries.length,
            ) !=
            null;
      },
      onAcceptWithDetails: (details) {
        final actions = ref.read(fileOperationsActionsProvider.notifier);
        actions.handleDragAndDrop(
          context,
          details.data.sourceSide,
          widget.side,
          details.data.entries,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;

        return Container(
          color: isDropTarget
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            interactive: true,
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: state.activeTab.entries.length,
              itemBuilder: (context, index) {
                final entry = state.activeTab.entries[index];
                final isSelected = state.activeTab.selectedPaths.contains(
                  entry.path,
                );

                final isEditing = entry.path == _editingEntryPath;

                final calculatedSize = _calculatedSizes[entry.path];
                final isCalculating =
                    _calculatedSizes.containsKey(entry.path) &&
                    calculatedSize == null;

                return _FileListTile(
                  entry: entry,
                  isSelected: isSelected,
                  isActivePanel: _isActive,
                  side: widget.side,
                  panelState: state,
                  sizeColWidth: _sizeColWidth,
                  dateColWidth: _dateColWidth,
                  calculatedSize: calculatedSize,
                  isCalculating: isCalculating,
                  isEditing: isEditing,
                  renameController: isEditing ? _renameController : null,
                  renameFocusNode: isEditing ? _renameFocusNode : null,
                  onRenameSubmitted: isEditing ? (_) => _commitRename() : null,
                  onTap: ({isControl = false, isShift = false}) => _onEntryTap(
                    entry,
                    isControlPressed: isControl,
                    isShiftPressed: isShift,
                  ),
                  onDoubleTap: () => _onEntryDoubleTap(entry),
                  onSecondaryTap: (position) =>
                      _onEntrySecondaryTap(entry, position),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    gen.AppLocalizations l10n,
    PanelState state,
  ) {
    final count = state.activeTab.entries.length;
    final selected = state.activeTab.selectionCount;
    final theme = Theme.of(context);

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      showBorder: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            selected > 0
                ? l10n.itemsSelected(selected)
                : l10n.itemsCount(count),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (selected > 0)
            Text(
              _formatTotalSize(state.activeTab.selectedEntries),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const Spacer(),
          DiskSpaceIndicator(
            providerId: state.activeTab.providerId,
            path: state.activeTab.currentPath,
          ),
        ],
      ),
    );
  }

  String _formatTotalSize(List<FileEntry> entries) {
    var total = 0;
    for (final e in entries) {
      if (!e.isDirectory) total += e.size;
    }
    return filesize(total);
  }

  void _showFolderPropertiesDialog(BuildContext context, FileEntry entry) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settings = ref.read(settingsProvider);
    final currentVal = settings.folderColors[entry.path];

    final colors = [
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.purple,
      Colors.pink,
      Colors.brown,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.folder,
              color: currentVal != null
                  ? Color(currentVal)
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(l10n.actionProperties),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'İsim: ${entry.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Yol: ${entry.path}',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Klasör Rengi Seçin:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 320,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...colors.map((color) {
                    final isSelected = currentVal == color.value;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        ref
                            .read(settingsProvider.notifier)
                            .setFolderColor(entry.path, color);
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 2.5,
                                )
                              : Border.all(color: Colors.black26, width: 0.5),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    );
                  }),
                  // Reset button
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setFolderColor(entry.path, null);
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26, width: 0.5),
                      ),
                      child: Icon(
                        Icons.clear,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }
}

/// A single file/directory tile in the list
class _FileListTile extends ConsumerWidget {
  const _FileListTile({
    required this.entry,
    required this.isSelected,
    required this.isActivePanel,
    required this.side,
    required this.panelState,
    required this.sizeColWidth,
    required this.dateColWidth,
    this.calculatedSize,
    this.isCalculating = false,
    this.isEditing = false,
    this.renameController,
    this.renameFocusNode,
    this.onRenameSubmitted,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTap,
  });

  final FileEntry entry;
  final bool isSelected;
  final bool isActivePanel;
  final PanelId side;
  final PanelState panelState;
  final double sizeColWidth;
  final double dateColWidth;
  final int? calculatedSize;
  final bool isCalculating;
  final bool isEditing;
  final TextEditingController? renameController;
  final FocusNode? renameFocusNode;
  final void Function(String)? onRenameSubmitted;
  final void Function({bool isControl, bool isShift}) onTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset) onSecondaryTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Color? backgroundColor;
    if (isSelected) {
      backgroundColor = isActivePanel
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : theme.colorScheme.primary.withValues(alpha: 0.08);
    }

    final formattedDate = entry.modified != null
        ? '${entry.modified!.day.toString().padLeft(2, '0')}.${entry.modified!.month.toString().padLeft(2, '0')}.${entry.modified!.year} ${entry.modified!.hour.toString().padLeft(2, '0')}:${entry.modified!.minute.toString().padLeft(2, '0')}'
        : '';

    final tileContent = GestureDetector(
      onTap: () {
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        onTap(isControl: ctrl, isShift: shift);
      },
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: (details) => onSecondaryTap(details.globalPosition),
      onLongPressStart: (details) => onSecondaryTap(details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          color: backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final showSize = w > 160;
              final showDate = w > 260;
              return Row(
                children: [
                  // Icon + Name - always visible
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          _getIcon(entry),
                          size: 18,
                          color: entry.isDirectory
                              ? (ref
                                            .watch(settingsProvider)
                                            .folderColors[entry.path] !=
                                        null
                                    ? Color(
                                        ref
                                            .watch(settingsProvider)
                                            .folderColors[entry.path]!,
                                      )
                                    : theme.colorScheme.primary)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: isEditing
                              ? SizedBox(
                                  height: 20,
                                  child: TextField(
                                    controller: renameController,
                                    focusNode: renameFocusNode,
                                    onSubmitted: onRenameSubmitted,
                                    style: theme.textTheme.bodyMedium,
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.only(
                                        bottom: 12,
                                      ), // Adjust alignment
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                )
                              : panelState.activeTab.searchQuery != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      entry.path,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 10,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                )
                              : Text(
                                  entry.name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                        if (entry.symlink) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.link,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Size - only when panel is wide enough
                  if (showSize)
                    SizedBox(
                      width: sizeColWidth,
                      child: isCalculating
                          ? const Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Text(
                              entry.isDirectory
                                  ? (calculatedSize != null
                                        ? filesize(calculatedSize!)
                                        : '')
                                  : filesize(entry.size),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.right,
                            ),
                    ),
                  // Date - only when panel is wide enough
                  if (showDate)
                    SizedBox(
                      width: dateColWidth,
                      child: Text(
                        formattedDate,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (Platform.isAndroid || Platform.isIOS)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Builder(
                        builder: (ctx) => InkWell(
                          onTap: () {
                            final box = ctx.findRenderObject() as RenderBox?;
                            if (box != null) {
                              final offset = box.localToGlobal(
                                Offset(box.size.width / 2, box.size.height / 2),
                              );
                              onSecondaryTap(offset);
                            } else {
                              onSecondaryTap(Offset.zero);
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_vert, size: 16),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

    if (isEditing) return tileContent;

    final dragEntries =
        isSelected && panelState.activeTab.selectedEntries.isNotEmpty
        ? panelState.activeTab.selectedEntries
        : [entry];

    final feedbackWidget = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getIcon(dragEntries.first),
              size: 24,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            if (dragEntries.length > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${dragEntries.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      return LongPressDraggable<PanelDragData>(
        data: PanelDragData(sourceSide: side, entries: dragEntries),
        feedback: feedbackWidget,
        childWhenDragging: Opacity(opacity: 0.5, child: tileContent),
        child: tileContent,
      );
    }

    return Draggable<PanelDragData>(
      data: PanelDragData(sourceSide: side, entries: dragEntries),
      feedback: feedbackWidget,
      childWhenDragging: Opacity(opacity: 0.5, child: tileContent),
      child: tileContent,
    );
  }

  IconData _getIcon(FileEntry entry) {
    if (entry.isDirectory) {
      return entry.isShared ? Icons.folder_shared : Icons.folder;
    }

    final ext = entry.extension;
    return switch (ext) {
      'png' ||
      'jpg' ||
      'jpeg' ||
      'gif' ||
      'bmp' ||
      'svg' ||
      'webp' => Icons.image,
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.description,
      'xls' || 'xlsx' => Icons.table_chart,
      'ppt' || 'pptx' => Icons.slideshow,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip,
      'mp3' || 'wav' || 'flac' || 'aac' || 'ogg' => Icons.audio_file,
      'mp4' || 'avi' || 'mkv' || 'mov' || 'webm' => Icons.video_file,
      'txt' || 'md' => Icons.text_snippet,
      'json' || 'xml' || 'yaml' || 'yml' => Icons.code,
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'java' ||
      'c' ||
      'cpp' ||
      'h' => Icons.code,
      'exe' || 'app' || 'sh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }
}
