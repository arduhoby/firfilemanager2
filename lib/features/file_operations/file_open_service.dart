import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/providers/local_provider.dart';
import '../../core/storage/storage_provider.dart';

part 'file_open_service.g.dart';

enum FileOpenPlatform { macOS, windows, linux, android, unsupported }

enum FileOpenOperation { defaultApplication, application }

enum EditFileResult { opened, downloadPageOpened, failed }

const nativeFileActionsChannel = MethodChannel('fir_file_manager/file_actions');

class FileOpenCommand {
  const FileOpenCommand(
    this.executable,
    this.arguments, {
    this.waitForExit = true,
  });

  final String executable;
  final List<String> arguments;
  final bool waitForExit;
}

FileOpenPlatform get currentFileOpenPlatform {
  if (Platform.isMacOS) return FileOpenPlatform.macOS;
  if (Platform.isWindows) return FileOpenPlatform.windows;
  if (Platform.isLinux) return FileOpenPlatform.linux;
  if (Platform.isAndroid) return FileOpenPlatform.android;
  return FileOpenPlatform.unsupported;
}

FileOpenCommand? resolveFileOpenCommand({
  required FileOpenPlatform platform,
  required FileOpenOperation operation,
  required String path,
  String? applicationPath,
}) {
  switch (operation) {
    case FileOpenOperation.defaultApplication:
      return switch (platform) {
        FileOpenPlatform.macOS => FileOpenCommand('open', [path]),
        FileOpenPlatform.windows => FileOpenCommand('cmd', [
          '/c',
          'start',
          '',
          path,
        ]),
        FileOpenPlatform.linux => FileOpenCommand('xdg-open', [path]),
        FileOpenPlatform.android || FileOpenPlatform.unsupported => null,
      };
    case FileOpenOperation.application:
      if (applicationPath == null || applicationPath.isEmpty) return null;
      return switch (platform) {
        FileOpenPlatform.macOS => FileOpenCommand('open', [
          '-a',
          applicationPath,
          path,
        ]),
        FileOpenPlatform.windows || FileOpenPlatform.linux => FileOpenCommand(
          applicationPath,
          [path],
          waitForExit: false,
        ),
        FileOpenPlatform.android || FileOpenPlatform.unsupported => null,
      };
  }
}

FileOpenCommand? resolvePlatformEditorCommand({
  required FileOpenPlatform platform,
  required String path,
}) => switch (platform) {
  FileOpenPlatform.macOS => FileOpenCommand('open', ['-e', path]),
  FileOpenPlatform.windows => FileOpenCommand('notepad.exe', [
    path,
  ], waitForExit: false),
  FileOpenPlatform.linux ||
  FileOpenPlatform.android ||
  FileOpenPlatform.unsupported => null,
};

String? preferredEditorName(FileOpenPlatform platform) => switch (platform) {
  FileOpenPlatform.macOS => 'TextEdit',
  FileOpenPlatform.windows => 'Notepad',
  FileOpenPlatform.linux => 'Kate',
  FileOpenPlatform.android || FileOpenPlatform.unsupported => null,
};

FileOpenCommand resolveKateOpenCommand({
  required String katePath,
  required String filePath,
}) => FileOpenCommand(katePath, [filePath], waitForExit: false);

bool supportsTerminalOpen(FileOpenPlatform platform) => switch (platform) {
  FileOpenPlatform.macOS ||
  FileOpenPlatform.windows ||
  FileOpenPlatform.linux => true,
  FileOpenPlatform.android || FileOpenPlatform.unsupported => false,
};

bool supportsTerminalOpenForProvider({
  required FileOpenPlatform platform,
  required StorageProvider provider,
}) => supportsTerminalOpen(platform) && provider is LocalProvider;

String _encodePowerShellCommand(String command) {
  final bytes = <int>[];
  for (final codeUnit in command.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return base64Encode(bytes);
}

List<FileOpenCommand> resolveTerminalOpenCommands({
  required FileOpenPlatform platform,
  required String path,
}) => switch (platform) {
  FileOpenPlatform.macOS => [
    FileOpenCommand('open', ['-a', 'Terminal', path]),
  ],
  FileOpenPlatform.windows => [
    FileOpenCommand('wt.exe', ['-d', path], waitForExit: false),
    FileOpenCommand('cmd.exe', [
      '/d',
      '/s',
      '/c',
      'start',
      '',
      'powershell.exe',
      '-NoExit',
      '-EncodedCommand',
      _encodePowerShellCommand(
        "Set-Location -LiteralPath '${path.replaceAll("'", "''")}'",
      ),
    ]),
  ],
  FileOpenPlatform.linux => [
    FileOpenCommand('x-terminal-emulator', [
      '--working-directory=$path',
    ], waitForExit: false),
    FileOpenCommand('gnome-terminal', [
      '--working-directory=$path',
    ], waitForExit: false),
    FileOpenCommand('konsole', ['--workdir', path], waitForExit: false),
    FileOpenCommand('xfce4-terminal', [
      '--working-directory=$path',
    ], waitForExit: false),
    FileOpenCommand('kitty', ['--directory', path], waitForExit: false),
  ],
  FileOpenPlatform.android || FileOpenPlatform.unsupported => const [],
};

Future<bool> invokeNativeFileAction(
  String method,
  String path, {
  MethodChannel channel = nativeFileActionsChannel,
}) async {
  try {
    return await channel.invokeMethod<bool>(method, {'path': path}) ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

const kateDownloadUrl = 'https://kate-editor.org/get-it/';

/// Service for opening files with the system default application.
///
/// Uses platform-specific commands:
/// - macOS: `open`
/// - Windows: `start`
/// - Linux: `xdg-open`
@Riverpod(keepAlive: true)
class FileOpenService extends _$FileOpenService {
  @override
  void build() {
    // No state needed
  }

  Future<bool> _execute(FileOpenCommand? command) async {
    if (command == null) return false;

    try {
      if (command.waitForExit) {
        final result = await Process.run(command.executable, command.arguments);
        return result.exitCode == 0;
      }

      await Process.start(
        command.executable,
        command.arguments,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Open a file or directory with the system default application.
  Future<bool> openWithDefault(String path) {
    if (currentFileOpenPlatform == FileOpenPlatform.android) {
      return invokeNativeFileAction('openFile', path);
    }
    return _execute(
      resolveFileOpenCommand(
        platform: currentFileOpenPlatform,
        operation: FileOpenOperation.defaultApplication,
        path: path,
      ),
    );
  }

  Future<String?> _findKate() async {
    try {
      final result = await Process.run('which', ['kate']);
      if (result.exitCode != 0) return null;

      for (final line in result.stdout.toString().split(RegExp(r'[\r\n]+'))) {
        final candidate = line.trim();
        if (candidate.isNotEmpty) return candidate;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<EditFileResult> _editWithKate(String path) async {
    final katePath = await _findKate();
    if (katePath != null) {
      final opened = await _execute(
        resolveKateOpenCommand(katePath: katePath, filePath: path),
      );
      return opened ? EditFileResult.opened : EditFileResult.failed;
    }

    try {
      final launched = await launchUrl(
        Uri.parse(kateDownloadUrl),
        mode: LaunchMode.externalApplication,
      );
      return launched
          ? EditFileResult.downloadPageOpened
          : EditFileResult.failed;
    } catch (_) {
      return EditFileResult.failed;
    }
  }

  /// Open a file in the platform's preferred editor.
  Future<EditFileResult> edit(String path) async {
    final platform = currentFileOpenPlatform;
    if (platform == FileOpenPlatform.linux) {
      return _editWithKate(path);
    }
    if (platform == FileOpenPlatform.android) {
      final opened = await invokeNativeFileAction('editFile', path);
      return opened ? EditFileResult.opened : EditFileResult.failed;
    }

    final opened = await _execute(
      resolvePlatformEditorCommand(platform: platform, path: path),
    );
    return opened ? EditFileResult.opened : EditFileResult.failed;
  }

  /// Open a file with a user-selected application.
  Future<bool> openWithApplication(String path, String applicationPath) =>
      _execute(
        resolveFileOpenCommand(
          platform: currentFileOpenPlatform,
          operation: FileOpenOperation.application,
          path: path,
          applicationPath: applicationPath,
        ),
      );

  /// Ask the user to choose an application and open the file.
  Future<bool> chooseAppAndOpen(String path) async {
    if (Platform.isAndroid) {
      return invokeNativeFileAction('chooseAppAndOpen', path);
    }

    try {
      String? applicationPath;
      String? initialDirectory;
      List<String>? allowedExtensions;

      if (Platform.isMacOS) {
        applicationPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Şununla Aç... (Lütfen bir .app seçin)',
          initialDirectory: '/Applications',
        );
      } else if (Platform.isWindows) {
        initialDirectory = 'C:\\Program Files';
        allowedExtensions = ['exe', 'bat', 'cmd'];
      } else if (Platform.isLinux) {
        initialDirectory = '/usr/bin';
      } else {
        return false;
      }

      if (!Platform.isMacOS) {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Şununla Aç...',
          initialDirectory: initialDirectory,
          type: allowedExtensions != null ? FileType.custom : FileType.any,
          allowedExtensions: allowedExtensions,
        );
        applicationPath = result != null && result.files.isNotEmpty
            ? result.files.single.path
            : null;
      }

      if (applicationPath == null || applicationPath.isEmpty) return false;
      return openWithApplication(path, applicationPath);
    } catch (_) {
      return false;
    }
  }

  /// Reveal a file in Finder/Explorer
  Future<bool> revealInFileManager(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Open a terminal at the specified path
  Future<bool> openInTerminal(
    String path, {
    required StorageProvider provider,
  }) async {
    if (!supportsTerminalOpenForProvider(
          platform: currentFileOpenPlatform,
          provider: provider,
        ) ||
        !await Directory(path).exists()) {
      return false;
    }

    for (final command in resolveTerminalOpenCommands(
      platform: currentFileOpenPlatform,
      path: path,
    )) {
      if (await _execute(command)) return true;
    }
    return false;
  }
}
