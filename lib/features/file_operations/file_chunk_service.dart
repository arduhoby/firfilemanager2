import 'dart:io';

import '../../core/storage/models/file_entry.dart';
import '../../core/storage/models/transfer_progress.dart';

final RegExp filePartPattern = RegExp(r'^(.*)\.part(\d{4})$');

class FilePartInfo {
  const FilePartInfo({required this.baseName, required this.number});

  final String baseName;
  final int number;

  static FilePartInfo? parse(String name) {
    final match = filePartPattern.firstMatch(name);
    if (match == null) return null;
    return FilePartInfo(
      baseName: match.group(1)!,
      number: int.parse(match.group(2)!),
    );
  }
}

class FileChunkService {
  const FileChunkService();

  Future<int> split({
    required FileEntry entry,
    required int partSizeBytes,
    required void Function(TransferProgress progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (entry.isDirectory || partSizeBytes <= 0) {
      throw ArgumentError('Parçalama için geçerli bir dosya ve boyut gerekir.');
    }
    final source = File(entry.path);
    final totalBytes = await source.length();
    final partCount = totalBytes == 0 ? 1 : (totalBytes / partSizeBytes).ceil();
    if (partCount > 9999) {
      throw StateError('Dosya 9999 parçadan fazlasını gerektiriyor.');
    }

    final outputs = <File>[];
    final temporary = <File>[];
    IOSink? sink;
    var transferred = 0;
    try {
      for (var index = 1; index <= partCount; index++) {
        final output = File(
          '${entry.path}.part${index.toString().padLeft(4, '0')}',
        );
        if (await output.exists()) {
          throw FileSystemException('Parça dosyası zaten var', output.path);
        }
        outputs.add(output);
        temporary.add(File('${output.path}.fir-partial'));
      }

      var partIndex = 0;
      var bytesInPart = 0;
      sink = temporary.first.openWrite();
      await for (final bytes in source.openRead()) {
        var offset = 0;
        while (offset < bytes.length) {
          if (cancelToken?.isCancelled ?? false) {
            throw const FileChunkCancelled();
          }
          final writable = partSizeBytes - bytesInPart;
          final count = (bytes.length - offset).clamp(0, writable).toInt();
          sink!.add(bytes.sublist(offset, offset + count));
          offset += count;
          bytesInPart += count;
          transferred += count;
          onProgress(
            TransferProgress(
              operation: TransferOperation.write,
              state: TransferState.inProgress,
              currentFile: entry,
              bytesTransferred: transferred,
              totalBytes: totalBytes,
            ),
          );
          if (bytesInPart == partSizeBytes && partIndex + 1 < partCount) {
            await sink!.flush();
            await sink!.close();
            partIndex++;
            bytesInPart = 0;
            sink = temporary[partIndex].openWrite();
          }
        }
      }
      await sink!.flush();
      await sink!.close();
      sink = null;
      if (totalBytes == 0) await temporary.first.writeAsBytes(const []);
      for (var index = 0; index < outputs.length; index++) {
        await temporary[index].rename(outputs[index].path);
      }
      onProgress(
        TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.completed,
          currentFile: entry,
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
          filesTransferred: partCount,
          totalFiles: partCount,
        ),
      );
      return partCount;
    } on FileChunkCancelled {
      onProgress(
        TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
          currentFile: entry,
          bytesTransferred: transferred,
          totalBytes: totalBytes,
        ),
      );
      rethrow;
    } finally {
      await sink?.close();
      for (final file in temporary) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<String> merge({
    required List<FileEntry> entries,
    required void Function(TransferProgress progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    final ordered = validatePartFamily(entries);
    final first = ordered.first;
    final info = FilePartInfo.parse(first.name)!;
    final output = File(
      '${File(first.path).parent.path}${Platform.pathSeparator}${info.baseName}',
    );
    if (await output.exists()) {
      throw FileSystemException('Birleştirilecek dosya zaten var', output.path);
    }
    final temporary = File('${output.path}.fir-partial');
    final totalBytes = ordered.fold<int>(0, (sum, entry) => sum + entry.size);
    var transferred = 0;
    IOSink? sink;
    try {
      sink = temporary.openWrite();
      for (final entry in ordered) {
        await for (final bytes in File(entry.path).openRead()) {
          if (cancelToken?.isCancelled ?? false) {
            throw const FileChunkCancelled();
          }
          sink.add(bytes);
          transferred += bytes.length;
          onProgress(
            TransferProgress(
              operation: TransferOperation.write,
              state: TransferState.inProgress,
              currentFile: entry,
              bytesTransferred: transferred,
              totalBytes: totalBytes,
            ),
          );
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await temporary.rename(output.path);
      onProgress(
        TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.completed,
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
        ),
      );
      return output.path;
    } on FileChunkCancelled {
      onProgress(
        TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
          bytesTransferred: transferred,
          totalBytes: totalBytes,
        ),
      );
      rethrow;
    } finally {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static List<FileEntry> validatePartFamily(List<FileEntry> entries) {
    if (entries.isEmpty) throw ArgumentError('Parça dosyası seçilmedi.');
    final parsed = entries
        .map((entry) => FilePartInfo.parse(entry.name))
        .toList();
    if (parsed.any((part) => part == null) ||
        entries.any((entry) => entry.isDirectory)) {
      throw ArgumentError(
        'Seçimin tamamı geçerli parça dosyalarından oluşmalı.',
      );
    }
    final baseName = parsed.first!.baseName;
    if (parsed.any((part) => part!.baseName != baseName)) {
      throw ArgumentError('Seçilen parçalar aynı dosyaya ait değil.');
    }
    final ordered = List<FileEntry>.from(entries)
      ..sort(
        (a, b) => FilePartInfo.parse(
          a.name,
        )!.number.compareTo(FilePartInfo.parse(b.name)!.number),
      );
    for (var index = 0; index < ordered.length; index++) {
      if (FilePartInfo.parse(ordered[index].name)!.number != index + 1) {
        throw ArgumentError(
          'Parça numaraları part0001 ile başlayıp kesintisiz olmalı.',
        );
      }
    }
    return ordered;
  }
}

class FileChunkCancelled implements Exception {
  const FileChunkCancelled();
}
