import '../../../core/commands/command_id.dart';
import '../../../core/commands/command_registry.dart';
import '../../../core/commands/file_command.dart';
import '../commands/background/copy_current_path_command.dart';
import '../commands/background/create_file_command.dart';
import '../commands/background/create_folder_command.dart';
import '../commands/background/equalize_panel_path_command.dart';
import '../commands/background/open_terminal_here_command.dart';
import '../commands/background/refresh_command.dart';
import '../commands/background/reveal_current_folder_command.dart';
import '../commands/background/select_all_command.dart';
import '../commands/background/toggle_hidden_command.dart';
import '../commands/command_action.dart';
import '../commands/item/compress_password_zip_command.dart';
import '../commands/item/compress_tar_command.dart';
import '../commands/item/compress_tar_gz_command.dart';
import '../commands/item/compress_zip_command.dart';
import '../commands/item/copy_path_command.dart';
import '../commands/item/copy_selection_command.dart';
import '../commands/item/delete_command.dart';
import '../commands/item/edit_file_command.dart';
import '../commands/item/extract_command.dart';
import '../commands/item/move_selection_command.dart';
import '../commands/item/merge_file_parts_command.dart';
import '../commands/item/open_default_command.dart';
import '../commands/item/open_entry_command.dart';
import '../commands/item/open_terminal_command.dart';
import '../commands/item/open_with_command.dart';
import '../commands/item/paste_command.dart';
import '../commands/item/properties_command.dart';
import '../commands/item/quick_look_command.dart';
import '../commands/item/rename_command.dart';
import '../commands/item/reveal_command.dart';
import '../commands/item/share_smb_command.dart';
import '../commands/item/split_file_command.dart';

CommandRegistry buildFilePanelCommandRegistry(
  Map<CommandId, CommandAction> actions,
) {
  CommandAction action(CommandId id) {
    final callback = actions[id];
    if (callback == null) {
      throw ArgumentError('Missing FilePanel command callback for $id.');
    }
    return callback;
  }

  return CommandRegistry(<FileCommand>[
    OpenEntryCommand(action(CommandId.openEntry)),
    OpenDefaultCommand(action(CommandId.openDefault)),
    EditFileCommand(action(CommandId.editFile)),
    OpenWithCommand(action(CommandId.openWith)),
    QuickLookCommand(action(CommandId.quickLook)),
    RevealCommand(action(CommandId.reveal)),
    CopyPathCommand(action(CommandId.copyPath)),
    CopySelectionCommand(action(CommandId.copySelection)),
    MoveSelectionCommand(action(CommandId.moveSelection)),
    PasteCommand(action(CommandId.paste)),
    RenameCommand(action(CommandId.rename)),
    DeleteCommand(action(CommandId.delete)),
    CompressZipCommand(action(CommandId.compressZip)),
    CompressTarCommand(action(CommandId.compressTar)),
    CompressTarGzCommand(action(CommandId.compressTarGz)),
    CompressPasswordZipCommand(action(CommandId.compressPasswordZip)),
    ExtractCommand(action(CommandId.extract)),
    SplitFileCommand(action(CommandId.splitFile)),
    MergeFilePartsCommand(action(CommandId.mergeFileParts)),
    OpenTerminalCommand(action(CommandId.openTerminal)),
    ShareSmbCommand(action(CommandId.shareSmb)),
    PropertiesCommand(action(CommandId.properties)),
    CreateFolderCommand(action(CommandId.createFolder)),
    CreateFileCommand(action(CommandId.createFile)),
    ToggleHiddenCommand(action(CommandId.toggleHidden)),
    OpenTerminalHereCommand(action(CommandId.openTerminalHere)),
    RevealCurrentFolderCommand(action(CommandId.revealCurrentFolder)),
    CopyCurrentPathCommand(action(CommandId.copyCurrentPath)),
    EqualizePanelPathCommand(action(CommandId.equalizePanelPath)),
    SelectAllCommand(action(CommandId.selectAll)),
    RefreshCommand(action(CommandId.refresh)),
  ]);
}
