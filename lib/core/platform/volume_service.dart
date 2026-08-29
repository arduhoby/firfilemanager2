import 'dart:io';

/// Cross-platform operations for removable or separately mounted volumes.
///
/// The UI only calls this service; platform command details stay here so the
/// same eject/unmount behavior can be reused by the drive bar and sidebar.
class VolumeService {
  const VolumeService._();

  static bool canEject(String path) {
    if (Platform.isMacOS) {
      return path.startsWith('/Volumes/') && path != '/Volumes/';
    }
    if (Platform.isWindows) {
      final match = RegExp(r'^([A-Za-z]):\\$').firstMatch(path);
      if (match == null) return false;
      final systemDrive = (Platform.environment['SystemDrive'] ?? 'C:')
          .toUpperCase();
      return '${match.group(1)!.toUpperCase()}:' != systemDrive;
    }
    return false;
  }

  static Future<VolumeActionResult> eject(String path) async {
    if (!canEject(path)) {
      return const VolumeActionResult.failure(
        'Bu disk güvenli şekilde çıkarılamaz.',
      );
    }

    try {
      if (Platform.isMacOS) {
        final result = await Process.run('/usr/bin/diskutil', [
          'eject',
          path,
        ]).timeout(const Duration(seconds: 20));
        if (result.exitCode == 0) return const VolumeActionResult.success();
        return VolumeActionResult.failure(_output(result));
      }

      if (Platform.isWindows) {
        final letter = path.substring(0, 1).toUpperCase();
        // Shell.Application invokes the same safe-eject action exposed by
        // File Explorer and works for USB and optical drives without admin.
        final script =
            """
\$shell = New-Object -ComObject Shell.Application
\$drive = \$shell.Namespace(17).ParseName('$letter:')
if (\$null -eq \$drive) { exit 2 }
\$drive.InvokeVerb('Eject')
""";
        final result = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 20));
        if (result.exitCode == 0) return const VolumeActionResult.success();
        return VolumeActionResult.failure(_output(result));
      }
    } on Object catch (error) {
      return VolumeActionResult.failure(error.toString());
    }

    return const VolumeActionResult.failure('Bu platform desteklenmiyor.');
  }

  static String _output(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    return stderr.isNotEmpty ? stderr : stdout;
  }
}

class VolumeActionResult {
  const VolumeActionResult.success() : ok = true, message = null;
  const VolumeActionResult.failure(this.message) : ok = false;

  final bool ok;
  final String? message;
}
