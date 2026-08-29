import 'package:flutter/material.dart';

import '../../../core/commands/command_context.dart';
import '../../../core/commands/command_id.dart';
import '../../../core/commands/command_registry.dart';
import '../../../widgets/cascade_menu/cascade_menu.dart';

class ContextMenuSelection {
  const ContextMenuSelection({
    required this.commandId,
    this.arguments = const <String, Object?>{},
  });

  final CommandId commandId;
  final Map<String, Object?> arguments;
}

class FilePanelContextMenuModel {
  const FilePanelContextMenuModel({
    required this.items,
    required this.selections,
  });

  final List<CascadeMenuItem> items;
  final Map<String, ContextMenuSelection> selections;
}

class RecentApplicationMenuItem {
  const RecentApplicationMenuItem({required this.path, required this.label});

  final String path;
  final String label;
}

class FilePanelContextMenuLabels {
  const FilePanelContextMenuLabels({
    required this.open,
    required this.openDefault,
    required this.edit,
    required this.openWith,
    required this.chooseApplication,
    required this.quickLook,
    required this.reveal,
    required this.copyPath,
    required this.copy,
    required this.move,
    required this.paste,
    required this.rename,
    required this.delete,
    required this.compress,
    required this.compressZip,
    required this.compressTar,
    required this.compressTarGz,
    required this.compressPasswordZip,
    required this.extract,
    this.fileParts = 'Parçala / Birleştir',
    this.splitFile = 'Parçala',
    this.mergeFileParts = 'Birleştir',
    required this.shareSmb,
    required this.stopSharingSmb,
    required this.properties,
    required this.newFolder,
    required this.newFile,
    required this.showHidden,
    required this.hideHidden,
    required this.openTerminal,
    required this.equalizePanel,
    required this.selectAll,
    required this.refresh,
  });

  final String open;
  final String openDefault;
  final String edit;
  final String openWith;
  final String chooseApplication;
  final String quickLook;
  final String reveal;
  final String copyPath;
  final String copy;
  final String move;
  final String paste;
  final String rename;
  final String delete;
  final String compress;
  final String compressZip;
  final String compressTar;
  final String compressTarGz;
  final String compressPasswordZip;
  final String extract;
  final String fileParts;
  final String splitFile;
  final String mergeFileParts;
  final String shareSmb;
  final String stopSharingSmb;
  final String properties;
  final String newFolder;
  final String newFile;
  final String showHidden;
  final String hideHidden;
  final String openTerminal;
  final String equalizePanel;
  final String selectAll;
  final String refresh;
}

class FilePanelContextMenuInput {
  const FilePanelContextMenuInput({
    required this.context,
    required this.labels,
    required this.hasEntry,
    required this.entryIsDirectory,
    required this.entryIsArchive,
    required this.entryIsShared,
    required this.recentApplications,
    this.editorName,
  });

  final CommandContext context;
  final FilePanelContextMenuLabels labels;
  final bool hasEntry;
  final bool entryIsDirectory;
  final bool entryIsArchive;
  final bool entryIsShared;
  final List<RecentApplicationMenuItem> recentApplications;
  final String? editorName;
}

class FilePanelContextMenuBuilder {
  FilePanelContextMenuBuilder(this._registry);

  final CommandRegistry _registry;
  final Map<String, ContextMenuSelection> _selections =
      <String, ContextMenuSelection>{};
  int _sequence = 0;

  FilePanelContextMenuModel build(FilePanelContextMenuInput input) {
    _selections.clear();
    _sequence = 0;
    final items = input.hasEntry
        ? _buildEntryMenu(input)
        : _buildBackgroundMenu(input);
    return FilePanelContextMenuModel(
      items: List<CascadeMenuItem>.unmodifiable(items),
      selections: Map<String, ContextMenuSelection>.unmodifiable(_selections),
    );
  }

  List<CascadeMenuItem> _buildEntryMenu(FilePanelContextMenuInput input) {
    final labels = input.labels;
    final context = input.context;
    final items = <CascadeMenuItem>[];
    if (input.entryIsDirectory) {
      _add(
        items,
        _leaf(context, CommandId.openEntry, labels.open, Icons.folder_open),
      );
      _add(
        items,
        _leaf(
          context,
          CommandId.openTerminal,
          labels.openTerminal,
          Icons.terminal,
        ),
      );
    } else {
      _add(
        items,
        _leaf(context, CommandId.openDefault, labels.openDefault, Icons.launch),
      );
      final editLabel = input.editorName == null
          ? labels.edit
          : '${labels.edit} (${input.editorName})';
      _add(
        items,
        _leaf(context, CommandId.editFile, editLabel, Icons.edit_note),
      );
      final openWithChildren = <CascadeMenuItem>[];
      for (final application in input.recentApplications) {
        _add(
          openWithChildren,
          _leaf(
            context,
            CommandId.openWith,
            application.label,
            Icons.launch,
            arguments: <String, Object?>{'applicationPath': application.path},
          ),
        );
      }
      _add(
        openWithChildren,
        _leaf(
          context,
          CommandId.openWith,
          labels.chooseApplication,
          Icons.apps,
        ),
      );
      if (openWithChildren.isNotEmpty) {
        items.add(
          CascadeMenuItem(
            value: 'submenu-open-with',
            label: labels.openWith,
            icon: Icons.open_in_new,
            children: openWithChildren,
          ),
        );
      }
    }
    _add(
      items,
      _leaf(context, CommandId.quickLook, labels.quickLook, Icons.visibility),
    );
    _add(items, _leaf(context, CommandId.reveal, labels.reveal, Icons.search));
    _add(
      items,
      _leaf(context, CommandId.copyPath, labels.copyPath, Icons.copy_all),
    );
    _divider(items);
    _add(
      items,
      _leaf(context, CommandId.copySelection, labels.copy, Icons.copy),
    );
    _add(
      items,
      _leaf(context, CommandId.moveSelection, labels.move, Icons.cut),
    );
    _add(items, _leaf(context, CommandId.paste, labels.paste, Icons.paste));
    _add(items, _leaf(context, CommandId.rename, labels.rename, Icons.edit));
    _add(
      items,
      _leaf(
        context,
        CommandId.delete,
        labels.delete,
        Icons.delete,
        destructive: true,
      ),
    );
    _divider(items);
    final archiveChildren = <CascadeMenuItem>[];
    _add(
      archiveChildren,
      _leaf(
        context,
        CommandId.compressZip,
        labels.compressZip,
        Icons.folder_zip,
      ),
    );
    _add(
      archiveChildren,
      _leaf(
        context,
        CommandId.compressTar,
        labels.compressTar,
        Icons.archive_outlined,
      ),
    );
    _add(
      archiveChildren,
      _leaf(
        context,
        CommandId.compressTarGz,
        labels.compressTarGz,
        Icons.compress,
      ),
    );
    _divider(archiveChildren);
    _add(
      archiveChildren,
      _leaf(
        context,
        CommandId.compressPasswordZip,
        labels.compressPasswordZip,
        Icons.lock_outline,
      ),
    );
    if (archiveChildren.isNotEmpty) {
      items.add(
        CascadeMenuItem(
          value: 'submenu-compress',
          label: labels.compress,
          icon: Icons.archive_outlined,
          children: archiveChildren,
        ),
      );
    }
    if (input.entryIsArchive) {
      _add(
        items,
        _leaf(context, CommandId.extract, labels.extract, Icons.unarchive),
      );
    }
    final partChildren = <CascadeMenuItem>[];
    _add(
      partChildren,
      _leaf(context, CommandId.splitFile, labels.splitFile, Icons.call_split),
    );
    _add(
      partChildren,
      _leaf(
        context,
        CommandId.mergeFileParts,
        labels.mergeFileParts,
        Icons.merge_type,
      ),
    );
    if (partChildren.isNotEmpty) {
      items.add(
        CascadeMenuItem(
          value: 'submenu-file-parts',
          label: labels.fileParts,
          icon: Icons.splitscreen,
          children: partChildren,
        ),
      );
    }
    _add(
      items,
      _leaf(
        context,
        CommandId.shareSmb,
        input.entryIsShared ? labels.stopSharingSmb : labels.shareSmb,
        input.entryIsShared ? Icons.link_off : Icons.share,
      ),
    );
    _divider(items);
    _add(
      items,
      _leaf(
        context,
        CommandId.properties,
        labels.properties,
        Icons.info_outline,
      ),
    );
    return items;
  }

  List<CascadeMenuItem> _buildBackgroundMenu(FilePanelContextMenuInput input) {
    final labels = input.labels;
    final context = input.context;
    final items = <CascadeMenuItem>[];
    _add(
      items,
      _leaf(
        context,
        CommandId.createFolder,
        labels.newFolder,
        Icons.create_new_folder,
      ),
    );
    _add(
      items,
      _leaf(context, CommandId.createFile, labels.newFile, Icons.note_add),
    );
    _add(items, _leaf(context, CommandId.paste, labels.paste, Icons.paste));
    _add(
      items,
      _leaf(
        context,
        CommandId.toggleHidden,
        context.showHidden ? labels.hideHidden : labels.showHidden,
        context.showHidden ? Icons.visibility_off : Icons.visibility,
      ),
    );
    _add(
      items,
      _leaf(
        context,
        CommandId.openTerminalHere,
        labels.openTerminal,
        Icons.terminal,
      ),
    );
    _add(
      items,
      _leaf(
        context,
        CommandId.revealCurrentFolder,
        labels.reveal,
        Icons.search,
      ),
    );
    _add(
      items,
      _leaf(
        context,
        CommandId.copyCurrentPath,
        labels.copyPath,
        Icons.copy_all,
      ),
    );
    _divider(items);
    _add(
      items,
      _leaf(
        context,
        CommandId.equalizePanelPath,
        labels.equalizePanel,
        Icons.drag_handle,
      ),
    );
    _add(
      items,
      _leaf(context, CommandId.selectAll, labels.selectAll, Icons.select_all),
    );
    _add(
      items,
      _leaf(context, CommandId.refresh, labels.refresh, Icons.refresh),
    );
    return items;
  }

  CascadeMenuItem? _leaf(
    CommandContext context,
    CommandId commandId,
    String label,
    IconData icon, {
    Map<String, Object?> arguments = const <String, Object?>{},
    bool destructive = false,
  }) {
    final commandContext = context.withArguments(arguments);
    final availability = _registry.resolve(commandId).evaluate(commandContext);
    if (!availability.visible) return null;
    final value = '${commandId.name}#${_sequence++}';
    _selections[value] = ContextMenuSelection(
      commandId: commandId,
      arguments: Map<String, Object?>.unmodifiable(arguments),
    );
    return CascadeMenuItem(
      value: value,
      label: label,
      icon: icon,
      enabled: availability.enabled,
      isDestructive: destructive,
    );
  }

  static void _add(List<CascadeMenuItem> items, CascadeMenuItem? item) {
    if (item != null) items.add(item);
  }

  static void _divider(List<CascadeMenuItem> items) {
    if (items.isNotEmpty && !items.last.isDivider) {
      items.add(const CascadeMenuItem.divider());
    }
  }
}
