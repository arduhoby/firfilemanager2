import 'dart:io';

import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/features/file_operations/file_chunk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits and merges a file without changing its bytes', () async {
    final directory = await Directory.systemTemp.createTemp('file_chunk_test_');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/sample.bin');
    final bytes = List<int>.generate(13, (index) => index + 1);
    await source.writeAsBytes(bytes);
    final entry = FileEntry(
      name: 'sample.bin',
      path: source.path,
      isDirectory: false,
      size: bytes.length,
    );

    final count = await const FileChunkService().split(
      entry: entry,
      partSizeBytes: 5,
      onProgress: (_) {},
    );

    expect(count, 3);
    expect(
      await File('${source.path}.part0001').readAsBytes(),
      bytes.sublist(0, 5),
    );
    expect(
      await File('${source.path}.part0002').readAsBytes(),
      bytes.sublist(5, 10),
    );
    expect(
      await File('${source.path}.part0003').readAsBytes(),
      bytes.sublist(10),
    );

    await source.delete();
    final parts = <FileEntry>[];
    for (var index = 1; index <= 3; index++) {
      final file = File(
        '${source.path}.part${index.toString().padLeft(4, '0')}',
      );
      parts.add(
        FileEntry(
          name: file.uri.pathSegments.last,
          path: file.path,
          isDirectory: false,
          size: await file.length(),
        ),
      );
    }
    await const FileChunkService().merge(
      entries: parts.reversed.toList(),
      onProgress: (_) {},
    );

    expect(await source.readAsBytes(), bytes);
  });

  test('rejects an incomplete part family', () {
    final entries = [
      FileEntry(
        name: 'a.bin.part0001',
        path: '/a.bin.part0001',
        isDirectory: false,
      ),
      FileEntry(
        name: 'a.bin.part0003',
        path: '/a.bin.part0003',
        isDirectory: false,
      ),
    ];
    expect(
      () => FileChunkService.validatePartFamily(entries),
      throwsArgumentError,
    );
  });
}
