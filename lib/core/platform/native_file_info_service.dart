import 'dart:io';

/// Opens the operating system's native file information UI when available.
class NativeFileInfoService {
  const NativeFileInfoService._();

  static Future<bool> show(String path) async {
    if (!Platform.isMacOS) return false;
    final file = File(path);
    if (!file.existsSync() && !Directory(path).existsSync()) return false;

    final escaped = path.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    try {
      final result = await Process.run('/usr/bin/osascript', [
        '-e',
        'tell application "Finder" to open information window of '
            '(POSIX file "$escaped" as alias)',
      ]).timeout(const Duration(seconds: 10));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }
}
