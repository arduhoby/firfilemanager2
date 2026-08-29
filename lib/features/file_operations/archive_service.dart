import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/models/file_entry.dart';
import '../../core/storage/models/transfer_progress.dart';
import 'archive_compression_engine.dart';
import 'archive_models.dart';

export 'archive_models.dart';

part 'archive_service.g.dart';

/// Service for compressing and extracting archives.
///
/// Supports:
/// - ZIP (create + extract)
/// - TAR (create + extract)
/// - TAR.GZ (create + extract)
@Riverpod(keepAlive: true)
class ArchiveService extends _$ArchiveService {
  final ArchiveCompressionEngine _compressionEngine =
      ArchiveCompressionEngine();

  @override
  void build() {
    ref.onDispose(_compressionEngine.cancel);
  }

  /// Compress files/directories into an archive
  Stream<TransferProgress> compress({
    required List<FileEntry> entries,
    required String destDir,
    required String archiveName,
    required ArchiveFormat format,
    String? password,
    CancelToken? cancelToken,
  }) async* {
    yield* _compressionEngine.compress(
      entries: entries,
      destinationDirectory: destDir,
      archiveName: archiveName,
      format: format,
      password: password,
      cancelToken: cancelToken,
    );
  }

  Future<int> checkAvailableSpace({
    required List<FileEntry> entries,
    required Iterable<String> destinationDirectories,
    required ArchiveFormat format,
  }) => _compressionEngine.checkAvailableSpace(
    entries: entries,
    destinationDirectories: destinationDirectories,
    format: format,
  );

  Future<ArchiveManifest> createManifest(List<FileEntry> entries) =>
      _compressionEngine.createManifest(entries);

  Future<void> checkManifestAvailableSpace({
    required ArchiveManifest manifest,
    required Iterable<String> destinationDirectories,
    required ArchiveFormat format,
  }) => _compressionEngine.checkManifestAvailableSpace(
    manifest: manifest,
    destinationDirectories: destinationDirectories,
    format: format,
  );

  Stream<TransferProgress> compressManifest({
    required ArchiveManifest manifest,
    required String destDir,
    required String archiveName,
    required ArchiveFormat format,
    String? password,
    CancelToken? cancelToken,
  }) => _compressionEngine.compressManifest(
    manifest: manifest,
    destinationDirectory: destDir,
    archiveName: archiveName,
    format: format,
    password: password,
    cancelToken: cancelToken,
  );

  String archivePath({
    required String destinationDirectory,
    required String archiveName,
    required ArchiveFormat format,
  }) => _compressionEngine.archivePath(
    destinationDirectory: destinationDirectory,
    archiveName: archiveName,
    format: format,
  );

  Stream<TransferProgress> copyArchiveTo({
    required ArchiveManifest manifest,
    required String sourceArchivePath,
    required String destDir,
    required String archiveName,
    required ArchiveFormat format,
    CancelToken? cancelToken,
  }) => _compressionEngine.copyArchiveTo(
    manifest: manifest,
    sourceArchivePath: sourceArchivePath,
    destinationDirectory: destDir,
    archiveName: archiveName,
    format: format,
    cancelToken: cancelToken,
  );

  void cancelCurrentOperation() => _compressionEngine.cancel();

  /// Extract an archive to a directory
  ///
  /// [archivePath] — path to the archive file
  /// [destDir] — destination directory
  /// Extract an archive to a directory asynchronously without blocking RAM.
  Stream<TransferProgress> extract({
    required String archivePath,
    required String destDir,
    String? password,
  }) async* {
    final inputFile = File(archivePath);
    if (!inputFile.existsSync()) {
      throw Exception('Archive not found: $archivePath');
    }

    final totalBytes = inputFile.lengthSync();
    final ext = p.extension(archivePath).toLowerCase();
    final ext2 = p
        .extension(p.basenameWithoutExtension(archivePath))
        .toLowerCase();

    // Create smart dest dir. We name it by archive name without extension
    final archiveName = p.basenameWithoutExtension(archivePath);
    final smartDestDir = p.join(destDir, archiveName);
    Directory(smartDestDir).createSync(recursive: true);

    Process process;

    if (ext == '.zip') {
      if (password != null && password.isNotEmpty) {
        process = await Process.start('unzip', [
          '-P',
          '-',
          '-o',
          archivePath,
          '-d',
          smartDestDir,
          '-x',
          '__MACOSX/*',
          '*/._*',
        ]);
        process.stdin.writeln(password);
        await process.stdin.close();
      } else {
        process = await Process.start('unzip', [
          '-o',
          archivePath,
          '-d',
          smartDestDir,
          '-x',
          '__MACOSX/*',
          '*/._*',
        ]);
      }
    } else if (ext == '.tar' ||
        (ext2 == '.tar' && ext == '.gz') ||
        (ext2 == '.tgz')) {
      final flags = ext == '.gz' ? '-xzf' : '-xf';
      process = await Process.start('tar', [
        flags,
        archivePath,
        '-C',
        smartDestDir,
      ]);
    } else if (ext == '.gz') {
      // Plain gzip
      final outputFile = p.join(smartDestDir, archiveName);
      process = await Process.start('sh', [
        '-c',
        'gunzip -c "$archivePath" > "$outputFile"',
      ]);
    } else {
      throw Exception('Unsupported archive format: $ext');
    }

    final stdoutStream = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    final stderrStream = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final stderrBuffer = StringBuffer();
    stderrStream.listen((line) {
      stderrBuffer.writeln(line);
    });

    int filesProcessed = 0;

    await for (final line in stdoutStream) {
      String? fileName;
      if (ext == '.zip') {
        if (line.contains('inflating: ') || line.contains('extracting: ')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            fileName = parts[1].trim();
          }
        }
      } else {
        fileName = line.trim();
      }

      if (fileName != null && fileName.isNotEmpty && !fileName.endsWith('/')) {
        filesProcessed++;
        // Approximate bytes based on files
        int progressBytes = (filesProcessed * 1024 * 1024); // fake progress
        if (progressBytes > totalBytes) progressBytes = totalBytes;

        yield TransferProgress(
          operation: TransferOperation.unzip,
          state: TransferState.inProgress,
          currentFile: FileEntry(
            name: p.basename(fileName),
            path: p.join(smartDestDir, fileName),
            isDirectory: false,
            size: 0,
            modified: DateTime.now(),
          ),
          totalBytes: totalBytes,
          bytesTransferred: progressBytes,
        );
      }
    }

    final exitCode = await process.exitCode;

    if (exitCode != 0 && exitCode != 1 && exitCode != 2) {
      if (exitCode == 82) {
        throw Exception('Hatalı şifre (Wrong password).');
      }
      throw Exception(
        'Arşiv çıkarma hatası (Exit code: $exitCode): ${stderrBuffer.toString()}',
      );
    }

    yield TransferProgress(
      operation: TransferOperation.unzip,
      state: TransferState.completed,
      totalBytes: totalBytes,
      bytesTransferred: totalBytes,
    );
  }

  /// Check if a file is a supported archive format
  bool isArchive(String path) {
    final ext = p.extension(path).toLowerCase();
    final ext2 = p.extension(p.basenameWithoutExtension(path)).toLowerCase();
    return ext == '.zip' ||
        ext == '.tar' ||
        ext == '.gz' ||
        (ext2 == '.tar' && ext == '.gz');
  }

  /// Check if the zip file is encrypted (requires macOS native `unzip`)
  Future<bool> isEncryptedZip(String archivePath) async {
    final ext = p.extension(archivePath).toLowerCase();
    if (ext != '.zip') return false;

    try {
      final result = await Process.run('unzip', ['-Z', '-v', archivePath]);
      return result.stdout.toString().toLowerCase().contains('encrypted');
    } catch (e) {
      return false;
    }
  }
}
