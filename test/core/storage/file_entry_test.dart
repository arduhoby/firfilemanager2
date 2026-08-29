import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileEntry', () {
    test('creates with required fields', () {
      final entry = FileEntry(
        name: 'test.txt',
        path: '/home/user/test.txt',
        isDirectory: false,
        size: 1024,
      );

      expect(entry.name, 'test.txt');
      expect(entry.path, '/home/user/test.txt');
      expect(entry.isDirectory, false);
      expect(entry.size, 1024);
      expect(entry.hidden, false);
      expect(entry.symlink, false);
    });

    test('extension returns lowercase extension without dot', () {
      final entry = FileEntry(
        name: 'photo.PNG',
        path: '/photos/photo.PNG',
        isDirectory: false,
      );
      expect(entry.extension, 'png');
    });

    test('extension returns empty for directories', () {
      final entry = FileEntry(
        name: 'Documents',
        path: '/home/user/Documents',
        isDirectory: true,
      );
      expect(entry.extension, '');
    });

    test('extension returns empty for files without extension', () {
      final entry = FileEntry(
        name: 'Makefile',
        path: '/project/Makefile',
        isDirectory: false,
      );
      expect(entry.extension, '');
    });

    test('parentPath returns parent directory', () {
      final entry = FileEntry(
        name: 'test.txt',
        path: '/home/user/test.txt',
        isDirectory: false,
      );
      expect(entry.parentPath, '/home/user');
    });

    test('isRoot returns true for root path', () {
      final entry = FileEntry(
        name: '/',
        path: '/',
        isDirectory: true,
      );
      expect(entry.isRoot, true);
    });

    test('isRoot returns false for non-root path', () {
      final entry = FileEntry(
        name: 'home',
        path: '/home',
        isDirectory: true,
      );
      expect(entry.isRoot, false);
    });

    test('copyWith creates a copy with updated fields', () {
      final original = FileEntry(
        name: 'old.txt',
        path: '/old.txt',
        isDirectory: false,
        size: 100,
      );

      final copy = original.copyWith(name: 'new.txt', size: 200);

      expect(copy.name, 'new.txt');
      expect(copy.size, 200);
      expect(copy.path, '/old.txt'); // unchanged
      expect(copy.isDirectory, false); // unchanged
    });

    test('equality is based on path and name', () {
      final entry1 = FileEntry(name: 'test.txt', path: '/test.txt', isDirectory: false);
      final entry2 = FileEntry(name: 'test.txt', path: '/test.txt', isDirectory: true, size: 999);
      final entry3 = FileEntry(name: 'other.txt', path: '/other.txt', isDirectory: false);

      expect(entry1 == entry2, true); // same path + name
      expect(entry1 == entry3, false);
      expect(entry1.hashCode, entry2.hashCode);
    });
  });
}