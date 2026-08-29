import 'package:fir_file_manager/core/storage/providers/local_provider.dart';
import 'package:fir_file_manager/features/file_operations/file_open_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../core/storage/mock_storage_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(nativeFileActionsChannel, null);
  });

  group('resolveFileOpenCommand', () {
    test('uses each platform default application command', () {
      const path = '/tmp/report with spaces.txt';

      final macOS = resolveFileOpenCommand(
        platform: FileOpenPlatform.macOS,
        operation: FileOpenOperation.defaultApplication,
        path: path,
      );
      final windows = resolveFileOpenCommand(
        platform: FileOpenPlatform.windows,
        operation: FileOpenOperation.defaultApplication,
        path: path,
      );
      final linux = resolveFileOpenCommand(
        platform: FileOpenPlatform.linux,
        operation: FileOpenOperation.defaultApplication,
        path: path,
      );

      expect(macOS?.executable, 'open');
      expect(macOS?.arguments, [path]);
      expect(windows?.executable, 'cmd');
      expect(windows?.arguments, ['/c', 'start', '', path]);
      expect(linux?.executable, 'xdg-open');
      expect(linux?.arguments, [path]);
    });

    test('passes a selected application and file as separate arguments', () {
      const applicationPath = '/opt/My Editor/bin/editor';
      const filePath = '/tmp/a file; rm -rf.txt';

      final command = resolveFileOpenCommand(
        platform: FileOpenPlatform.linux,
        operation: FileOpenOperation.application,
        path: filePath,
        applicationPath: applicationPath,
      );

      expect(command?.executable, applicationPath);
      expect(command?.arguments, [filePath]);
      expect(command?.waitForExit, isFalse);
    });

    test('rejects unsupported platforms and empty application paths', () {
      expect(
        resolveFileOpenCommand(
          platform: FileOpenPlatform.unsupported,
          operation: FileOpenOperation.defaultApplication,
          path: '/tmp/file.txt',
        ),
        isNull,
      );
      expect(
        resolveFileOpenCommand(
          platform: FileOpenPlatform.linux,
          operation: FileOpenOperation.application,
          path: '/tmp/file.txt',
          applicationPath: '',
        ),
        isNull,
      );
    });
  });

  group('platform editors', () {
    test('uses TextEdit on macOS', () {
      final command = resolvePlatformEditorCommand(
        platform: FileOpenPlatform.macOS,
        path: '/tmp/file.txt',
      );

      expect(command?.executable, 'open');
      expect(command?.arguments, ['-e', '/tmp/file.txt']);
      expect(preferredEditorName(FileOpenPlatform.macOS), 'TextEdit');
    });

    test('uses Notepad on Windows', () {
      final command = resolvePlatformEditorCommand(
        platform: FileOpenPlatform.windows,
        path: r'C:\Documents\file.txt',
      );

      expect(command?.executable, 'notepad.exe');
      expect(command?.arguments, [r'C:\Documents\file.txt']);
      expect(command?.waitForExit, isFalse);
      expect(preferredEditorName(FileOpenPlatform.windows), 'Notepad');
    });

    test('launches Kate directly on Linux', () {
      final command = resolveKateOpenCommand(
        katePath: '/usr/bin/kate',
        filePath: '/tmp/file.txt',
      );

      expect(command.executable, '/usr/bin/kate');
      expect(command.arguments, ['/tmp/file.txt']);
      expect(command.waitForExit, isFalse);
      expect(preferredEditorName(FileOpenPlatform.linux), 'Kate');
    });

    test(
      'delegates Android editing to the native file action channel',
      () async {
        MethodCall? receivedCall;
        messenger.setMockMethodCallHandler(nativeFileActionsChannel, (
          call,
        ) async {
          receivedCall = call;
          return true;
        });

        final opened = await invokeNativeFileAction(
          'editFile',
          '/storage/emulated/0/Download/file.txt',
        );

        expect(opened, isTrue);
        expect(receivedCall?.method, 'editFile');
        expect(receivedCall?.arguments, {
          'path': '/storage/emulated/0/Download/file.txt',
        });
        expect(preferredEditorName(FileOpenPlatform.android), isNull);
      },
    );

    test('reports a failed Android native action', () async {
      messenger.setMockMethodCallHandler(nativeFileActionsChannel, (
        call,
      ) async {
        throw PlatformException(code: 'EDITOR_NOT_FOUND');
      });

      expect(
        await invokeNativeFileAction('editFile', '/tmp/file.txt'),
        isFalse,
      );
    });
  });

  group('terminal commands', () {
    test('supports Windows, macOS, and Linux desktops', () {
      expect(supportsTerminalOpen(FileOpenPlatform.windows), isTrue);
      expect(supportsTerminalOpen(FileOpenPlatform.macOS), isTrue);
      expect(supportsTerminalOpen(FileOpenPlatform.linux), isTrue);
      expect(supportsTerminalOpen(FileOpenPlatform.android), isFalse);
    });

    test('allows local and mounted drives but blocks remote providers', () {
      final localProvider = LocalProvider();
      final remoteProvider = MockStorageProvider();

      expect(
        supportsTerminalOpenForProvider(
          platform: FileOpenPlatform.windows,
          provider: localProvider,
        ),
        isTrue,
      );
      expect(
        supportsTerminalOpenForProvider(
          platform: FileOpenPlatform.linux,
          provider: localProvider,
        ),
        isTrue,
      );
      expect(
        supportsTerminalOpenForProvider(
          platform: FileOpenPlatform.windows,
          provider: remoteProvider,
        ),
        isFalse,
      );
      expect(
        supportsTerminalOpenForProvider(
          platform: FileOpenPlatform.android,
          provider: localProvider,
        ),
        isFalse,
      );
    });

    test('opens macOS Terminal at the selected directory', () {
      final commands = resolveTerminalOpenCommands(
        platform: FileOpenPlatform.macOS,
        path: '/Users/test/My Project',
      );

      expect(commands, hasLength(1));
      expect(commands.single.executable, 'open');
      expect(commands.single.arguments, [
        '-a',
        'Terminal',
        '/Users/test/My Project',
      ]);
    });

    test('uses Windows Terminal with a PowerShell fallback', () {
      final commands = resolveTerminalOpenCommands(
        platform: FileOpenPlatform.windows,
        path: r"C:\Work\Melih's Project",
      );

      expect(commands.first.executable, 'wt.exe');
      expect(commands.first.arguments, ['-d', r"C:\Work\Melih's Project"]);
      expect(commands[1].executable, 'cmd.exe');
      expect(commands[1].arguments, contains('-EncodedCommand'));
      expect(
        commands[1].arguments.join(' '),
        isNot(contains(r"C:\Work\Melih's Project")),
      );
    });

    test('provides common Linux terminal fallbacks', () {
      final commands = resolveTerminalOpenCommands(
        platform: FileOpenPlatform.linux,
        path: '/home/test/My Project',
      );

      expect(commands.map((command) => command.executable), [
        'x-terminal-emulator',
        'gnome-terminal',
        'konsole',
        'xfce4-terminal',
        'kitty',
      ]);
    });
  });
}
