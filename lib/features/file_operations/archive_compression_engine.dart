import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/models/file_entry.dart';
import '../../core/storage/models/transfer_progress.dart';
import '../../core/storage/providers/local_provider.dart';
import 'archive_models.dart';

class ArchiveCompressionEngine {
  Isolate? _activeIsolate;
  CancelToken? _activeToken;

  Future<ArchiveManifest> createManifest(List<FileEntry> entries) async {
    final sources = entries
        .map(
          (entry) => _ArchiveSource(
            path: entry.path,
            name: entry.name,
            isDirectory: entry.isDirectory,
          ),
        )
        .toList(growable: false);
    final items = await Isolate.run(() => _collectItemsInIsolate(sources));
    return ArchiveManifest(items);
  }

  static List<ArchiveManifestItem> _collectItemsInIsolate(
    List<_ArchiveSource> entries,
  ) {
    final items = <ArchiveManifestItem>[];
    for (final entry in entries) {
      if (!entry.isDirectory) {
        final file = File(entry.path);
        if (file.existsSync()) {
          items.add(
            ArchiveManifestItem(
              filePath: file.path,
              archivePath: _archivePath(entry.name),
              size: file.lengthSync(),
            ),
          );
        }
        continue;
      }

      final directory = Directory(entry.path);
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: entry.path);
        items.add(
          ArchiveManifestItem(
            filePath: entity.path,
            archivePath: _archivePath(p.join(entry.name, relative)),
            size: entity.lengthSync(),
          ),
        );
      }
    }
    return items;
  }

  Future<int> checkAvailableSpace({
    required List<FileEntry> entries,
    required Iterable<String> destinationDirectories,
    required ArchiveFormat format,
  }) async {
    final manifest = await createManifest(entries);
    await checkManifestAvailableSpace(
      manifest: manifest,
      destinationDirectories: destinationDirectories,
      format: format,
    );
    return manifest.totalBytes;
  }

  Future<void> checkManifestAvailableSpace({
    required ArchiveManifest manifest,
    required Iterable<String> destinationDirectories,
    required ArchiveFormat format,
  }) async {
    if (manifest.totalFiles == 0) {
      throw StateError('Sıkıştırılacak dosya bulunamadı.');
    }
    final sourceBytes = manifest.totalBytes;
    final required = ArchiveSpacePolicy.requiredBytes(
      sourceBytes,
      format: format,
    );
    final provider = LocalProvider();

    for (final path in destinationDirectories.toSet()) {
      final info = await provider.getDiskSpaceInfo(path);
      if (info == null) throw ArchiveSpaceUnavailableException(path);
      if (required > info.freeBytes) {
        throw ArchiveInsufficientSpaceException(
          path: path,
          requiredBytes: required,
          availableBytes: info.freeBytes,
        );
      }
    }
  }

  Stream<TransferProgress> compress({
    required List<FileEntry> entries,
    required String destinationDirectory,
    required String archiveName,
    required ArchiveFormat format,
    String? password,
    CancelToken? cancelToken,
  }) async* {
    final manifest = await createManifest(entries);
    await checkManifestAvailableSpace(
      manifest: manifest,
      destinationDirectories: [destinationDirectory],
      format: format,
    );
    yield* compressManifest(
      manifest: manifest,
      destinationDirectory: destinationDirectory,
      archiveName: archiveName,
      format: format,
      password: password,
      cancelToken: cancelToken,
    );
  }

  Stream<TransferProgress> compressManifest({
    required ArchiveManifest manifest,
    required String destinationDirectory,
    required String archiveName,
    required ArchiveFormat format,
    String? password,
    CancelToken? cancelToken,
  }) async* {
    if (manifest.totalFiles == 0) {
      throw StateError('Sıkıştırılacak dosya bulunamadı.');
    }

    final extension = _archiveExtension(format);
    final nonce = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    final outputPath = p.join(destinationDirectory, '$archiveName$extension');
    final partialPath = p.join(
      destinationDirectory,
      '$archiveName.partial-$nonce$extension',
    );
    final temporaryTarPath = '$partialPath.tar-work';
    final totalFiles = manifest.totalFiles;
    final sourceBytes = manifest.totalBytes;
    final displayTotalBytes = sourceBytes == 0 ? 1 : sourceBytes;
    final token = cancelToken ?? CancelToken();
    _activeToken = token;

    yield TransferProgress(
      operation: TransferOperation.zip,
      state: TransferState.inProgress,
      totalFiles: totalFiles,
      totalBytes: displayTotalBytes,
      overallTotalBytes: displayTotalBytes,
    );

    final receivePort = ReceivePort();
    try {
      _activeIsolate = await Isolate.spawn(
        _compressIsolate,
        _CompressConfig(
          items: manifest.items,
          partialPath: partialPath,
          temporaryTarPath: temporaryTarPath,
          format: format,
          password: password,
          sendPort: receivePort.sendPort,
        ),
      );
      token.onCancel(() {
        _activeIsolate?.kill(priority: Isolate.immediate);
        receivePort.sendPort.send(const {'type': 'cancelled'});
      });

      await for (final message in receivePort) {
        if (message is! Map) continue;
        final type = message['type'] as String?;
        if (type == 'progress') {
          final filePath = message['filePath'] as String;
          final size = message['size'] as int;
          final transferred = message['transferredBytes'] as int;
          yield TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.inProgress,
            currentFile: FileEntry(
              name: p.basename(filePath),
              path: filePath,
              isDirectory: false,
              size: size,
              modified: DateTime.now(),
            ),
            totalFiles: totalFiles,
            filesTransferred: message['filesTransferred'] as int,
            totalBytes: displayTotalBytes,
            bytesTransferred: transferred,
            overallTotalBytes: displayTotalBytes,
            overallBytesTransferred: transferred,
          );
          continue;
        }
        if (type == 'finalizing') {
          yield TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.inProgress,
            currentFile: FileEntry(
              name: 'Arşiv sonlandırılıyor…',
              path: partialPath,
              isDirectory: false,
              size: 0,
              modified: DateTime.now(),
            ),
            totalFiles: totalFiles,
            filesTransferred: totalFiles,
            totalBytes: displayTotalBytes,
            bytesTransferred: displayTotalBytes,
            overallTotalBytes: displayTotalBytes,
            overallBytesTransferred: displayTotalBytes,
          );
          continue;
        }
        if (type == 'error') {
          throw StateError(
            message['error']?.toString() ?? 'Arşivleme başarısız oldu.',
          );
        }
        if (type == 'cancelled') {
          yield TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.cancelled,
            totalFiles: totalFiles,
            totalBytes: displayTotalBytes,
            overallTotalBytes: displayTotalBytes,
          );
          return;
        }
        if (type == 'completed') break;
      }

      if (token.isCancelled) return;
      await _verifyPartialArchive(partialPath, format);
      await _replaceAtomically(partialPath, outputPath, nonce);
      yield TransferProgress(
        operation: TransferOperation.zip,
        state: TransferState.completed,
        totalFiles: totalFiles,
        filesTransferred: totalFiles,
        totalBytes: displayTotalBytes,
        bytesTransferred: displayTotalBytes,
        overallTotalBytes: displayTotalBytes,
        overallBytesTransferred: displayTotalBytes,
      );
    } finally {
      receivePort.close();
      _activeIsolate?.kill(priority: Isolate.immediate);
      _activeIsolate = null;
      _activeToken = null;
      await _deleteIfExists(partialPath);
      await _deleteIfExists(temporaryTarPath);
    }
  }

  String archivePath({
    required String destinationDirectory,
    required String archiveName,
    required ArchiveFormat format,
  }) =>
      p.join(destinationDirectory, '$archiveName${_archiveExtension(format)}');

  Stream<TransferProgress> copyArchiveTo({
    required ArchiveManifest manifest,
    required String sourceArchivePath,
    required String destinationDirectory,
    required String archiveName,
    required ArchiveFormat format,
    CancelToken? cancelToken,
  }) async* {
    final source = File(sourceArchivePath);
    if (!await source.exists()) {
      throw StateError('Kaynak arşiv bulunamadı: $sourceArchivePath');
    }

    final nonce = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    final outputPath = archivePath(
      destinationDirectory: destinationDirectory,
      archiveName: archiveName,
      format: format,
    );
    final partialPath = p.join(
      destinationDirectory,
      '$archiveName.partial-$nonce${_archiveExtension(format)}',
    );
    final totalBytes = await source.length();
    final displayTotalBytes = totalBytes == 0 ? 1 : totalBytes;
    final token = cancelToken ?? CancelToken();
    _activeToken = token;

    yield TransferProgress(
      operation: TransferOperation.zip,
      state: TransferState.inProgress,
      totalFiles: manifest.totalFiles,
      totalBytes: displayTotalBytes,
      overallTotalBytes: displayTotalBytes,
    );

    final sink = File(partialPath).openWrite();
    var sinkClosed = false;
    var transferred = 0;
    try {
      await for (final chunk in source.openRead()) {
        if (token.isCancelled) {
          yield TransferProgress(
            operation: TransferOperation.zip,
            state: TransferState.cancelled,
            totalFiles: manifest.totalFiles,
            totalBytes: displayTotalBytes,
            overallTotalBytes: displayTotalBytes,
          );
          return;
        }
        sink.add(chunk);
        transferred += chunk.length;
        yield TransferProgress(
          operation: TransferOperation.zip,
          state: TransferState.inProgress,
          currentFile: FileEntry(
            name: p.basename(sourceArchivePath),
            path: sourceArchivePath,
            isDirectory: false,
            size: totalBytes,
            modified: DateTime.now(),
          ),
          totalFiles: manifest.totalFiles,
          filesTransferred: manifest.totalFiles,
          totalBytes: displayTotalBytes,
          bytesTransferred: transferred,
          overallTotalBytes: displayTotalBytes,
          overallBytesTransferred: transferred,
        );
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
      await _verifyPartialArchive(partialPath, format);
      await _replaceAtomically(partialPath, outputPath, nonce);
      yield TransferProgress(
        operation: TransferOperation.zip,
        state: TransferState.completed,
        totalFiles: manifest.totalFiles,
        filesTransferred: manifest.totalFiles,
        totalBytes: displayTotalBytes,
        bytesTransferred: displayTotalBytes,
        overallTotalBytes: displayTotalBytes,
        overallBytesTransferred: displayTotalBytes,
      );
    } finally {
      if (!sinkClosed) await sink.close();
      _activeToken = null;
      await _deleteIfExists(partialPath);
    }
  }

  void cancel() {
    _activeToken?.cancel();
    _activeIsolate?.kill(priority: Isolate.immediate);
  }

  Future<void> _verifyPartialArchive(String path, ArchiveFormat format) async {
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('Arşiv doğrulanamadı: çıktı dosyası boş.');
    }
    final header = await file
        .openRead(0, 8)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    final valid = switch (format) {
      ArchiveFormat.zip =>
        header.length >= 4 && header[0] == 0x50 && header[1] == 0x4b,
      ArchiveFormat.tar => await file.length() >= 512,
      ArchiveFormat.tarGz =>
        header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b,
    };
    if (!valid) {
      throw StateError('Arşiv doğrulanamadı: geçersiz dosya başlığı.');
    }
  }

  Future<void> _replaceAtomically(
    String partialPath,
    String outputPath,
    String nonce,
  ) async {
    final output = File(outputPath);
    final backup = File('$outputPath.backup-$nonce');
    var movedExisting = false;
    try {
      if (await output.exists()) {
        await output.rename(backup.path);
        movedExisting = true;
      }
      await File(partialPath).rename(outputPath);
      if (movedExisting) await backup.delete();
    } catch (_) {
      if (!await output.exists() && movedExisting && await backup.exists()) {
        await backup.rename(outputPath);
      }
      rethrow;
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  static String _archivePath(String path) => path.replaceAll('\\', '/');

  static String _archiveExtension(ArchiveFormat format) => switch (format) {
    ArchiveFormat.zip => '.zip',
    ArchiveFormat.tar => '.tar',
    ArchiveFormat.tarGz => '.tar.gz',
  };
}

class _ArchiveSource {
  const _ArchiveSource({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  final String path;
  final String name;
  final bool isDirectory;
}

class _CompressConfig {
  const _CompressConfig({
    required this.items,
    required this.partialPath,
    required this.temporaryTarPath,
    required this.format,
    required this.password,
    required this.sendPort,
  });

  final List<ArchiveManifestItem> items;
  final String partialPath;
  final String temporaryTarPath;
  final ArchiveFormat format;
  final String? password;
  final SendPort sendPort;
}

Future<void> _compressIsolate(_CompressConfig config) async {
  try {
    switch (config.format) {
      case ArchiveFormat.zip:
        final encoder = ZipFileEncoder(password: config.password)
          ..create(config.partialPath);
        await _addItems(config, encoder.addFile);
        config.sendPort.send(const {'type': 'finalizing'});
        await encoder.close();
      case ArchiveFormat.tar:
        final encoder = TarFileEncoder()..create(config.partialPath);
        await _addItems(config, encoder.addFile);
        config.sendPort.send(const {'type': 'finalizing'});
        await encoder.close();
      case ArchiveFormat.tarGz:
        final encoder = TarFileEncoder()..create(config.temporaryTarPath);
        await _addItems(config, encoder.addFile);
        await encoder.close();
        config.sendPort.send(const {'type': 'finalizing'});
        await File(config.temporaryTarPath)
            .openRead()
            .transform(gzip.encoder)
            .pipe(File(config.partialPath).openWrite());
    }
    config.sendPort.send(const {'type': 'completed'});
  } catch (error, stackTrace) {
    config.sendPort.send({'type': 'error', 'error': '$error\n$stackTrace'});
  }
}

typedef _ArchiveFileAdder = Future<void> Function(File file, [String? name]);

Future<void> _addItems(
  _CompressConfig config,
  _ArchiveFileAdder addFile,
) async {
  var transferred = 0;
  for (var index = 0; index < config.items.length; index++) {
    final item = config.items[index];
    await addFile(File(item.filePath), item.archivePath);
    transferred += item.size;
    config.sendPort.send({
      'type': 'progress',
      'filePath': item.filePath,
      'size': item.size,
      'filesTransferred': index + 1,
      'transferredBytes': transferred,
    });
  }
}
