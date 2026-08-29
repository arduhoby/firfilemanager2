import 'package:fir_file_manager/core/commands/command_context.dart';
import 'package:fir_file_manager/core/commands/command_id.dart';
import 'package:fir_file_manager/core/commands/command_result.dart';
import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/features/context_menu/application/file_panel_command_registry.dart';
import 'package:fir_file_manager/features/context_menu/commands/command_action.dart';
import 'package:fir_file_manager/features/context_menu/presentation/file_panel_context_menu_builder.dart';
import 'package:fir_file_manager/widgets/cascade_menu/cascade_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final registry = buildFilePanelCommandRegistry(<CommandId, CommandAction>{
    for (final id in CommandId.values)
      id: (_) async => const CommandResult.completed(),
  });

  test('recent application path is carried as a typed command argument', () {
    final model = FilePanelContextMenuBuilder(registry).build(
      FilePanelContextMenuInput(
        context: _fileContext(),
        labels: _labels,
        hasEntry: true,
        entryIsDirectory: false,
        entryIsArchive: false,
        entryIsShared: false,
        recentApplications: const <RecentApplicationMenuItem>[
          RecentApplicationMenuItem(
            path: r'C:\Tools\Editor.exe',
            label: 'Editor.exe',
          ),
        ],
      ),
    );

    final selection = model.selections.values.singleWhere(
      (item) => item.arguments['applicationPath'] != null,
    );
    expect(selection.commandId, CommandId.openWith);
    expect(selection.arguments['applicationPath'], r'C:\Tools\Editor.exe');
  });

  test('terminal command is hidden for a remote provider', () {
    final model = FilePanelContextMenuBuilder(registry).build(
      FilePanelContextMenuInput(
        context: _directoryContext(isLocal: false),
        labels: _labels,
        hasEntry: true,
        entryIsDirectory: true,
        entryIsArchive: false,
        entryIsShared: false,
        recentApplications: const <RecentApplicationMenuItem>[],
      ),
    );

    expect(
      model.selections.values.any(
        (selection) => selection.commandId == CommandId.openTerminal,
      ),
      isFalse,
    );
  });

  test('background menu keeps valid UTF-8 Turkish labels', () {
    final model = FilePanelContextMenuBuilder(registry).build(
      FilePanelContextMenuInput(
        context: _directoryContext(isLocal: true, hasEntry: false),
        labels: _labels,
        hasEntry: false,
        entryIsDirectory: false,
        entryIsArchive: false,
        entryIsShared: false,
        recentApplications: const <RecentApplicationMenuItem>[],
      ),
    );
    final labels = _flatten(model.items).map((item) => item.label).toList();

    expect(labels, contains('Gizli dosyaları göster'));
    expect(labels, contains('Terminalde aç'));
    expect(labels, contains('Diğer Paneli Eşitle (=)'));
  });
}

CommandContext _fileContext() => CommandContext(
  sourcePanelId: 'panel-a',
  providerId: 'local',
  currentPath: r'C:\Files',
  clickedEntry: FileEntry(
    name: 'note.txt',
    path: r'C:\Files\note.txt',
    isDirectory: false,
  ),
  capabilities: const <CommandCapability>{
    CommandCapability.read,
    CommandCapability.write,
    CommandCapability.rename,
    CommandCapability.delete,
    CommandCapability.archive,
    CommandCapability.share,
    CommandCapability.localPath,
    CommandCapability.terminal,
  },
  hasClipboardEntries: true,
);

CommandContext _directoryContext({
  required bool isLocal,
  bool hasEntry = true,
}) => CommandContext(
  sourcePanelId: 'panel-a',
  providerId: isLocal ? 'local' : 'sftp-1',
  currentPath: isLocal ? r'C:\Files' : '/srv/files',
  clickedEntry: hasEntry
      ? FileEntry(
          name: 'folder',
          path: isLocal ? r'C:\Files\folder' : '/srv/files/folder',
          isDirectory: true,
        )
      : null,
  targetPanelIds: const <String>['panel-b'],
  capabilities: <CommandCapability>{
    CommandCapability.read,
    CommandCapability.write,
    CommandCapability.rename,
    CommandCapability.delete,
    CommandCapability.archive,
    CommandCapability.share,
    if (isLocal) CommandCapability.localPath,
    if (isLocal) CommandCapability.terminal,
  },
);

Iterable<CascadeMenuItem> _flatten(Iterable<CascadeMenuItem> items) sync* {
  for (final item in items) {
    yield item;
    final children = item.children;
    if (children != null) yield* _flatten(children);
  }
}

const _labels = FilePanelContextMenuLabels(
  open: 'Aç',
  openDefault: 'Varsayılanla Aç',
  edit: 'Düzenle',
  openWith: 'Birlikte Aç',
  chooseApplication: 'Uygulama Seç',
  quickLook: 'Önizle (Quick Look)',
  reveal: 'Dosya Yöneticisinde Göster',
  copyPath: 'Yolu Kopyala',
  copy: 'Kopyala',
  move: 'Taşı',
  paste: 'Yapıştır',
  rename: 'Yeniden Adlandır',
  delete: 'Sil',
  compress: 'Sıkıştırma',
  compressZip: 'ZIP',
  compressTar: 'TAR',
  compressTarGz: 'TAR.GZ',
  compressPasswordZip: 'Şifreli ZIP...',
  extract: 'Çıkart',
  shareSmb: 'SMB ile Paylaş',
  stopSharingSmb: 'SMB Paylaşımını Durdur / Düzenle',
  properties: 'Özellikler',
  newFolder: 'Yeni Klasör',
  newFile: 'Yeni Dosya',
  showHidden: 'Gizli dosyaları göster',
  hideHidden: 'Gizli dosyaları gizle',
  openTerminal: 'Terminalde aç',
  equalizePanel: 'Diğer Paneli Eşitle (=)',
  selectAll: 'Tümünü Seç',
  refresh: 'Yenile',
);
