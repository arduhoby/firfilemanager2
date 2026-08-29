import 'dart:io';

import 'package:fir_file_manager/core/storage/models/connection_profile.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/core/storage/providers/webdav_provider.dart';
import 'mock_storage_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class _MockWebdavClient extends Mock implements webdav.Client {}

class _RecordingProvider extends MockStorageProvider {
  List<int>? lastBytes;

  @override
  Stream<TransferProgress> write(
    String path,
    Stream<List<int>> data, {
    CancelToken? cancelToken,
  }) async* {
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    lastBytes = bytes;
    yield* super.write(path, Stream.value(bytes), cancelToken: cancelToken);
  }
}

WebdavProvider _provider(_MockWebdavClient client, {int chunkSize = 4}) =>
    WebdavProvider.withClient(
      profile: ConnectionProfile(type: ConnectionType.webdav, name: 'test'),
      password: null,
      client: client,
      chunkSize: chunkSize,
    );

webdav.File _remoteFile(String path, int size) =>
    webdav.File(path: path, isDir: false, size: size);

void _configureRemote(_MockWebdavClient client, Map<String, List<int>> remote) {
  when(() => client.readDir(any())).thenAnswer((invocation) async {
    final parent = invocation.positionalArguments[0] as String;
    return remote.entries
        .where(
          (entry) =>
              entry.key.substring(0, entry.key.lastIndexOf('/')) == parent,
        )
        .map((entry) => _remoteFile(entry.key, entry.value.length))
        .toList();
  });
  when(
    () => client.writeFromFile(
      any(),
      any(),
      cancelToken: any(named: 'cancelToken'),
    ),
  ).thenAnswer((invocation) async {
    final localPath = invocation.positionalArguments[0] as String;
    final remotePath = invocation.positionalArguments[1] as String;
    remote[remotePath] = await File(localPath).readAsBytes();
  });
  when(() => client.rename(any(), any(), any())).thenAnswer((invocation) async {
    final source = invocation.positionalArguments[0] as String;
    final destination = invocation.positionalArguments[1] as String;
    final bytes = remote.remove(source);
    if (bytes != null) remote[destination] = bytes;
  });
  when(() => client.remove(any())).thenAnswer((invocation) async {
    remote.remove(invocation.positionalArguments[0] as String);
  });
}

void main() {
  test('uploads a file at the threshold to its original path', () async {
    final client = _MockWebdavClient();
    final remote = <String, List<int>>{};
    _configureRemote(client, remote);

    final updates = await _provider(
      client,
    ).write('/docs/exact.bin', Stream.value(<int>[1, 2, 3, 4])).toList();

    expect(updates.last.state, TransferState.completed);
    expect(remote, {
      '/docs/exact.bin': [1, 2, 3, 4],
    });
  });

  test(
    'splits input chunks crossing the boundary and preserves bytes',
    () async {
      final client = _MockWebdavClient();
      final remote = <String, List<int>>{};
      _configureRemote(client, remote);

      final updates = await _provider(client)
          .write(
            '/docs/movie.bin',
            Stream.value(<int>[10, 11, 12, 13, 14, 15, 16]),
          )
          .toList();

      expect(updates.last.state, TransferState.completed);
      expect(
        remote.keys,
        containsAll(['/docs/movie.bin.part0001', '/docs/movie.bin.part0002']),
      );
      expect(remote['/docs/movie.bin.part0001'], [10, 11, 12, 13]);
      expect(remote['/docs/movie.bin.part0002'], [14, 15, 16]);
    },
  );

  test(
    'falls back to direct PUT when publishing a staged part with MOVE fails',
    () async {
      final client = _MockWebdavClient();
      final remote = <String, List<int>>{};
      _configureRemote(client, remote);
      when(() => client.rename(any(), any(), any())).thenAnswer((
        invocation,
      ) async {
        final source = invocation.positionalArguments[0] as String;
        if (source.contains('webdav-upload')) {
          throw Exception('MOVE not supported');
        }
      });

      final updates = await _provider(client)
          .write('/docs/movie.bin', Stream.value(<int>[1, 2, 3, 4, 5, 6]))
          .toList();

      expect(updates.last.state, TransferState.completed);
      expect(remote['/docs/movie.bin.part0001'], [1, 2, 3, 4]);
      expect(remote['/docs/movie.bin.part0002'], [5, 6]);
    },
  );

  test('honors cancellation before uploading a staged part', () async {
    final client = _MockWebdavClient();
    when(
      () => client.writeFromFile(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {});
    final token = CancelToken()..cancel();

    final updates = await _provider(client)
        .write(
          '/docs/cancelled.bin',
          Stream.value(<int>[1, 2, 3]),
          cancelToken: token,
        )
        .toList();

    expect(updates.last.state, TransferState.cancelled);
    verifyNever(
      () => client.writeFromFile(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
      ),
    );
  });

  test('replaces stale multipart tails when overwriting a file', () async {
    final client = _MockWebdavClient();
    final remote = <String, List<int>>{
      '/docs/movie.bin.part0001': [9, 9, 9, 9],
      '/docs/movie.bin.part0002': [8, 8, 8, 8],
      '/docs/movie.bin.part0003': [7],
    };
    _configureRemote(client, remote);

    final updates = await _provider(client)
        .write('/docs/movie.bin', Stream.value(<int>[1, 2, 3, 4, 5, 6, 7]))
        .toList();

    expect(updates.last.state, TransferState.completed);
    expect(
      remote.keys,
      containsAll(['/docs/movie.bin.part0001', '/docs/movie.bin.part0002']),
    );
    expect(remote.keys, isNot(contains('/docs/movie.bin.part0003')));
    expect(remote['/docs/movie.bin.part0001'], [1, 2, 3, 4]);
    expect(remote['/docs/movie.bin.part0002'], [5, 6, 7]);
  });

  test(
    'copy reassembles ordered siblings, including a .part0001 source path',
    () async {
      final client = _MockWebdavClient();
      final remote = <String, List<int>>{
        '/docs/archive.bin.part0002': [5, 6],
        '/docs/archive.bin.part0001': [1, 2, 3, 4],
      };
      when(() => client.readDir(any())).thenAnswer((invocation) async {
        final parent = invocation.positionalArguments[0] as String;
        return remote.entries
            .where(
              (entry) =>
                  entry.key.substring(0, entry.key.lastIndexOf('/')) == parent,
            )
            .map((entry) => _remoteFile(entry.key, entry.value.length))
            .toList();
      });
      when(
        () => client.read2File(
          any(),
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((invocation) async {
        final remotePath = invocation.positionalArguments[0] as String;
        final localPath = invocation.positionalArguments[1] as String;
        await File(localPath).writeAsBytes(remote[remotePath]!);
      });

      final destination = _RecordingProvider();
      final updates = await _provider(
        client,
      ).copy('/docs/archive.bin.part0001', destination, '/copied.bin').toList();

      expect(updates.last.state, TransferState.completed);
      expect(destination.lastBytes, [1, 2, 3, 4, 5, 6]);
      verify(
        () => client.read2File(
          '/docs/archive.bin.part0001',
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
      verify(
        () => client.read2File(
          '/docs/archive.bin.part0002',
          any(),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).called(1);
    },
  );
}
