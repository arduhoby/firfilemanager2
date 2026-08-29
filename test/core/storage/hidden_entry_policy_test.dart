import 'dart:io';

import 'package:fir_file_manager/core/storage/hidden_entry_policy.dart';
import 'package:fir_file_manager/core/storage/providers/local_provider.dart';
import 'package:fir_file_manager/core/storage/storage_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('HiddenEntryPolicy', () {
    test('treats dot-prefixed names as hidden on every platform', () {
      expect(HiddenEntryPolicy.isDotHidden('.git'), isTrue);
      expect(HiddenEntryPolicy.isDotHidden('.env'), isTrue);
      expect(HiddenEntryPolicy.isDotHidden('git'), isFalse);
    });

    test('parses Windows Hidden attributes', () {
      const output = '''
A    H               C:\\Work\\project\\.git
A                    C:\\Work\\project\\README.md
     H               C:\\Work\\project\\secret.txt
''';

      expect(HiddenEntryPolicy.parseWindowsAttribOutput(output), {
        HiddenEntryPolicy.normalizeWindowsPath(r'C:\Work\project\.git'),
        HiddenEntryPolicy.normalizeWindowsPath(r'C:\Work\project\secret.txt'),
      });
    });
  });

  group('LocalProvider hidden entries', () {
    late Directory tempDirectory;
    late LocalProvider provider;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'fir_hidden_entry_test_',
      );
      provider = LocalProvider(homePathOverride: tempDirectory.path);
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('hides and reveals a .git directory', () async {
      await Directory(p.join(tempDirectory.path, '.git')).create();
      await File(p.join(tempDirectory.path, 'README.md')).writeAsString('ok');

      final hidden = await provider.list(tempDirectory.path);
      final visible = await provider.list(
        tempDirectory.path,
        const ListOptions(showHidden: true),
      );

      expect(hidden.map((entry) => entry.name), isNot(contains('.git')));
      expect(visible.map((entry) => entry.name), contains('.git'));
      expect(
        visible.singleWhere((entry) => entry.name == '.git').hidden,
        isTrue,
      );
    });

    test('copies .git even while hidden in the panel', () async {
      final source = Directory(p.join(tempDirectory.path, 'source'));
      final git = Directory(p.join(source.path, '.git'));
      await git.create(recursive: true);
      await File(p.join(git.path, 'config')).writeAsString('[core]');
      await File(p.join(source.path, 'README.md')).writeAsString('project');

      final destination = p.join(tempDirectory.path, 'destination');
      final progress = await provider
          .copy(source.path, provider, destination)
          .toList();

      expect(progress.last.state.name, 'completed');
      expect(
        await File(p.join(destination, '.git', 'config')).exists(),
        isTrue,
      );
      expect(await File(p.join(destination, 'README.md')).exists(), isTrue);
    });

    test('honors the Windows Hidden attribute', () async {
      if (!Platform.isWindows) return;

      final hiddenFile = File(p.join(tempDirectory.path, 'secret.txt'));
      await hiddenFile.writeAsString('secret');
      final setHidden = await Process.run('attrib.exe', [
        '+H',
        hiddenFile.path,
      ]);
      expect(setHidden.exitCode, 0);

      try {
        final hidden = await provider.list(tempDirectory.path);
        final visible = await provider.list(
          tempDirectory.path,
          const ListOptions(showHidden: true),
        );

        expect(
          hidden.map((entry) => entry.name),
          isNot(contains('secret.txt')),
        );
        expect(
          visible.singleWhere((entry) => entry.name == 'secret.txt').hidden,
          isTrue,
        );
      } finally {
        await Process.run('attrib.exe', ['-H', hiddenFile.path]);
      }
    });
  });
}
