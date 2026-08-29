import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

const _excludedDirectories = <String>{
  '.dart_tool',
  '.git',
  '.gradle',
  '.idea',
  '.vscode',
  'Pods',
  'build',
  'dist',
  'ephemeral',
};

const _textExtensions = <String>{
  '.arb',
  '.c',
  '.cc',
  '.cmake',
  '.cpp',
  '.css',
  '.dart',
  '.gradle',
  '.h',
  '.hpp',
  '.html',
  '.ini',
  '.java',
  '.js',
  '.json',
  '.kt',
  '.kts',
  '.lock',
  '.manifest',
  '.md',
  '.pbxproj',
  '.plist',
  '.ps1',
  '.py',
  '.rc',
  '.sh',
  '.swift',
  '.toml',
  '.ts',
  '.xml',
  '.yaml',
  '.yml',
};

const _textFileNames = <String>{'.editorconfig', '.gitattributes'};

void main() {
  test('source text is valid UTF-8 and contains no mojibake markers', () async {
    final root = Directory.current.absolute;
    final failures = <String>[];

    await _scanDirectory(root, root, failures);

    expect(
      failures,
      isEmpty,
      reason: 'All source text must remain UTF-8:\n${failures.join('\n')}',
    );
  });
}

Future<void> _scanDirectory(
  Directory root,
  Directory directory,
  List<String> failures,
) async {
  await for (final entity in directory.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (entity is Directory) {
      if (!_excludedDirectories.contains(name)) {
        await _scanDirectory(root, entity, failures);
      }
      continue;
    }

    if (entity is! File ||
        (!_textFileNames.contains(name) &&
            !_textExtensions.contains(path.extension(name)))) {
      continue;
    }

    final relativePath = path.relative(entity.path, from: root.path);
    late final String content;
    try {
      content = utf8.decode(await entity.readAsBytes(), allowMalformed: false);
    } on FormatException catch (error) {
      failures.add('$relativePath: invalid UTF-8 ($error)');
      continue;
    }

    final lines = const LineSplitter().convert(content);
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      if (_containsSuspiciousEncodingMarker(lines[lineIndex])) {
        failures.add('$relativePath:${lineIndex + 1}: suspicious encoding');
      }
    }
  }
}

bool _containsSuspiciousEncodingMarker(String value) {
  final runes = value.runes.toList(growable: false);
  for (var index = 0; index < runes.length; index++) {
    final rune = runes[index];
    if (rune == 0x00c2 ||
        rune == 0x00c3 ||
        rune == 0x00c4 ||
        rune == 0x00c5 ||
        rune == 0xfffd ||
        (rune >= 0x0080 && rune <= 0x009f)) {
      return true;
    }

    if (rune == 0x00e2 && index + 1 < runes.length) {
      final next = runes[index + 1];
      if (next == 0x20ac ||
          next == 0x2020 ||
          next == 0x201d ||
          next == 0x201c) {
        return true;
      }
    }
  }
  return false;
}
