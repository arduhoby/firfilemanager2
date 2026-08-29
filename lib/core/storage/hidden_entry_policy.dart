import 'dart:io';

import 'package:path/path.dart' as p;

/// Canonical hidden-entry policy shared by local and remote storage providers.
class HiddenEntryPolicy {
  const HiddenEntryPolicy._();

  /// Unix-style hidden entries are supported consistently on every platform.
  static bool isDotHidden(String name) => name.startsWith('.');

  static bool isHidden(
    String name, {
    bool hasPlatformHiddenAttribute = false,
  }) => isDotHidden(name) || hasPlatformHiddenAttribute;

  static bool shouldInclude({
    required String name,
    required bool showHidden,
    bool hasPlatformHiddenAttribute = false,
  }) =>
      showHidden ||
      !isHidden(name, hasPlatformHiddenAttribute: hasPlatformHiddenAttribute);

  /// Reads the Windows Hidden attribute once per directory listing.
  ///
  /// Dot-prefixed entries do not depend on this lookup. If Windows refuses the
  /// attribute query, listing continues with the cross-platform dotfile rule.
  static Future<Set<String>> windowsHiddenPaths(String directoryPath) async {
    if (!Platform.isWindows) return const <String>{};

    try {
      final result = await Process.run('attrib.exe', [
        '/D',
        p.join(directoryPath, '*'),
      ]);
      if (result.exitCode != 0) return const <String>{};
      return parseWindowsAttribOutput(result.stdout.toString());
    } catch (_) {
      return const <String>{};
    }
  }

  static Set<String> parseWindowsAttribOutput(String output) {
    final hiddenPaths = <String>{};
    final linePattern = RegExp(r'^([A-Z ]+)\s+(.+)$');

    for (final rawLine in output.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;

      final match = linePattern.firstMatch(line);
      if (match == null) continue;

      final attributes = match.group(1)!.replaceAll(' ', '');
      if (!attributes.contains('H')) continue;

      final path = match.group(2)!.trim();
      if (path.isNotEmpty) hiddenPaths.add(normalizeWindowsPath(path));
    }
    return hiddenPaths;
  }

  static String normalizeWindowsPath(String path) =>
      p.windows.normalize(path).toLowerCase();
}
