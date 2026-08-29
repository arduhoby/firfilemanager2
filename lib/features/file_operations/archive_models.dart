import 'dart:math' as math;

enum ArchiveFormat { zip, tar, tarGz }

/// Immutable source snapshot shared by preflight, compression and fan-out.
class ArchiveManifest {
  ArchiveManifest(Iterable<ArchiveManifestItem> source)
    : items = List.unmodifiable(source) {
    totalFiles = items.length;
    totalBytes = items.fold<int>(0, (sum, item) => sum + item.size);
  }

  final List<ArchiveManifestItem> items;
  late final int totalFiles;
  late final int totalBytes;
}

class ArchiveManifestItem {
  const ArchiveManifestItem({
    required this.filePath,
    required this.archivePath,
    required this.size,
  });

  final String filePath;
  final String archivePath;
  final int size;
}

/// Conservative workspace required before an archive is created.
class ArchiveSpacePolicy {
  static const int minimumSafetyBytes = 512 * 1024 * 1024;

  static int requiredBytes(int sourceBytes, {required ArchiveFormat format}) {
    final safety = math.max(minimumSafetyBytes, (sourceBytes * 0.05).ceil());
    // TAR.GZ is produced through a temporary streaming TAR so neither the
    // source nor the archive is ever accumulated in memory.
    final temporaryTarBytes = format == ArchiveFormat.tarGz ? sourceBytes : 0;
    return sourceBytes + temporaryTarBytes + safety;
  }
}

class ArchiveInsufficientSpaceException implements Exception {
  const ArchiveInsufficientSpaceException({
    required this.path,
    required this.requiredBytes,
    required this.availableBytes,
  });

  final String path;
  final int requiredBytes;
  final int availableBytes;

  @override
  String toString() =>
      'Hedef disk alanı yetersiz: $path '
      '(gerekli: $requiredBytes bayt, kullanılabilir: $availableBytes bayt).';
}

class ArchiveSpaceUnavailableException implements Exception {
  const ArchiveSpaceUnavailableException(this.path);

  final String path;

  @override
  String toString() => 'Hedef diskin boş alanı ölçülemedi: $path';
}
