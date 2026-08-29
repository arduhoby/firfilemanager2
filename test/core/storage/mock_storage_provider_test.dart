import 'dart:async';
import 'dart:convert';

import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/core/storage/storage_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_storage_provider.dart';

void main() {
  late MockStorageProvider provider;

  setUp(() {
    provider = MockStorageProvider();
    // Seed with a basic filesystem
    provider.seed({
      '/': FileEntry(name: '/', path: '/', isDirectory: true),
      '/home': FileEntry(name: 'home', path: '/home', isDirectory: true),
      '/home/user': FileEntry(name: 'user', path: '/home/user', isDirectory: true),
      '/home/user/docs': FileEntry(name: 'docs', path: '/home/user/docs', isDirectory: true),
      '/home/user/readme.txt': FileEntry(
        name: 'readme.txt',
        path: '/home/user/readme.txt',
        isDirectory: false,
        size: 12,
        modified: DateTime(2024, 1, 15),
      ),
      '/home/user/.hidden': FileEntry(
        name: '.hidden',
        path: '/home/user/.hidden',
        isDirectory: false,
        size: 5,
        hidden: true,
      ),
      '/home/user/docs/report.pdf': FileEntry(
        name: 'report.pdf',
        path: '/home/user/docs/report.pdf',
        isDirectory: false,
        size: 2048,
      ),
    }, contents: {
      '/home/user/readme.txt': utf8.encode('Hello World!'),
      '/home/user/.hidden': utf8.encode('test'),
    });
  });

  group('MockStorageProvider', () {
    test('list returns entries in a directory', () async {
      final entries = await provider.list('/home/user');

      // .hidden is filtered by default, so: docs, readme.txt
      expect(entries.length, 2);
      expect(entries.any((e) => e.name == 'docs'), true);
      expect(entries.any((e) => e.name == 'readme.txt'), true);
    });

    test('list filters hidden files by default', () async {
      final entries = await provider.list('/home/user');

      expect(entries.any((e) => e.name == '.hidden'), false);
    });

    test('list shows hidden files when showHidden is true', () async {
      final entries = await provider.list('/home/user', const ListOptions(showHidden: true));

      expect(entries.any((e) => e.name == '.hidden'), true);
    });

    test('list returns empty for empty directory', () async {
      await provider.mkdir('/empty');
      final entries = await provider.list('/empty');
      expect(entries, isEmpty);
    });

    test('stat returns entry for existing path', () async {
      final entry = await provider.stat('/home/user/readme.txt');

      expect(entry.name, 'readme.txt');
      expect(entry.isDirectory, false);
      expect(entry.size, 12);
    });

    test('stat throws for non-existing path', () async {
      expect(
        () => provider.stat('/nonexistent'),
        throwsA(isA<StorageException>()),
      );
    });

    test('mkdir creates a new directory', () async {
      await provider.mkdir('/home/user/newfolder');

      final exists = await provider.exists('/home/user/newfolder');
      expect(exists, true);

      final entry = await provider.stat('/home/user/newfolder');
      expect(entry.isDirectory, true);
    });

    test('mkdir throws if directory already exists', () async {
      expect(
        () => provider.mkdir('/home/user'),
        throwsA(isA<StorageException>()),
      );
    });

    test('delete removes a file', () async {
      await provider.delete('/home/user/readme.txt');

      final exists = await provider.exists('/home/user/readme.txt');
      expect(exists, false);
    });

    test('delete removes a directory and its children', () async {
      await provider.delete('/home/user/docs');

      expect(await provider.exists('/home/user/docs'), false);
      expect(await provider.exists('/home/user/docs/report.pdf'), false);
    });

    test('move moves a file to a new path', () async {
      await provider.move('/home/user/readme.txt', '/home/user/moved.txt');

      expect(await provider.exists('/home/user/readme.txt'), false);
      expect(await provider.exists('/home/user/moved.txt'), true);

      final entry = await provider.stat('/home/user/moved.txt');
      expect(entry.name, 'moved.txt');
    });

    test('rename renames a file', () async {
      await provider.rename('/home/user/readme.txt', 'renamed.txt');

      expect(await provider.exists('/home/user/readme.txt'), false);
      expect(await provider.exists('/home/user/renamed.txt'), true);
    });

    test('exists returns true for existing path', () async {
      expect(await provider.exists('/home/user'), true);
    });

    test('exists returns false for non-existing path', () async {
      expect(await provider.exists('/nonexistent'), false);
    });

    test('read emits progress and completes', () async {
      final progressList = await provider.read('/home/user/readme.txt').toList();

      expect(progressList, isNotEmpty);
      expect(progressList.last.state, TransferState.completed);
      expect(progressList.last.bytesTransferred, 12);
      expect(progressList.last.totalBytes, 12);
    });

    test('read fails for non-existing file', () async {
      final progressList = await provider.read('/nonexistent').toList();

      expect(progressList.last.state, TransferState.failed);
    });

    test('read can be cancelled', () async {
      final cancelToken = CancelToken();
      cancelToken.cancel();

      final progressList = await provider
          .read('/home/user/readme.txt', cancelToken: cancelToken)
          .toList();

      expect(progressList.any((p) => p.state == TransferState.cancelled), true);
    });

    test('write creates a new file', () async {
      final data = Stream.fromIterable([utf8.encode('New content')]);

      final progressList = await provider.write('/home/user/new.txt', data).toList();

      expect(progressList.last.state, TransferState.completed);

      final exists = await provider.exists('/home/user/new.txt');
      expect(exists, true);
    });

    test('copy copies file to another provider', () async {
      final dest = MockStorageProvider();
      await dest.mkdir('/dest');

      await provider
          .copy('/home/user/readme.txt', dest, '/dest/readme.txt')
          .toList();

      final exists = await dest.exists('/dest/readme.txt');
      expect(exists, true);
    });

    test('normalizePath handles edge cases', () {
      expect(provider.normalizePath(''), '/');
      expect(provider.normalizePath('/'), '/');
      expect(provider.normalizePath('/home/'), '/home');
      expect(provider.normalizePath('//home//user'), '/home/user');
    });

    test('basename returns last path component', () {
      expect(provider.basename('/home/user/file.txt'), 'file.txt');
      expect(provider.basename('/'), '/');
    });

    test('dirname returns parent path', () {
      expect(provider.dirname('/home/user/file.txt'), '/home/user');
      expect(provider.dirname('/home'), '/');
      expect(provider.dirname('/'), '/');
    });

    test('joinPath joins parent and child', () {
      expect(provider.joinPath('/home', 'user'), '/home/user');
      expect(provider.joinPath('/home/', 'user'), '/home/user');
    });

    test('disconnect sets isConnected to false', () async {
      await provider.disconnect();
      expect(provider.isConnected, false);
    });

    test('list throws when not connected', () async {
      await provider.disconnect();
      expect(
        () => provider.list('/'),
        throwsA(isA<StorageException>()),
      );
    });
  });
}
