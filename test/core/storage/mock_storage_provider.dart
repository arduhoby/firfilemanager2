import 'dart:async';

import 'package:fir_file_manager/core/storage/models/connection_profile.dart';
import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/core/storage/storage_provider.dart';

/// A mock [StorageProvider] for testing.
///
/// Uses an in-memory virtual filesystem. All operations are synchronous
/// and deterministic, making tests fast and reliable.
class MockStorageProvider implements StorageProvider {
  MockStorageProvider({
    this.profile,
    this.displayName = 'Mock',
    Set<ProviderCapability>? supportedCapabilities,
  }) : supportedCapabilities =
           supportedCapabilities ?? ProviderCapability.values.toSet();

  @override
  final ConnectionProfile? profile;

  @override
  final String displayName;

  final Set<ProviderCapability> supportedCapabilities;

  /// In-memory filesystem: path → entry
  final Map<String, FileEntry> _entries = {};

  /// In-memory file contents: path → bytes
  final Map<String, List<int>> _contents = {};

  bool _isConnected = true;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateChanges => _connectionController.stream;

  /// Seed the mock filesystem with initial entries
  void seed(
    Map<String, FileEntry> entries, {
    Map<String, List<int>>? contents,
  }) {
    _entries.addAll(entries);
    if (contents != null) _contents.addAll(contents);
  }

  /// Add a single entry to the mock filesystem
  void addEntry(FileEntry entry, {List<int>? content}) {
    _entries[entry.path] = entry;
    if (content != null && !entry.isDirectory) {
      _contents[entry.path] = content;
    }
  }

  @override
  Future<void> connect() async {
    _isConnected = true;
    _connectionController.add(true);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionController.add(false);
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!_isConnected) {
      throw StorageException(
        'Not connected',
        code: StorageException.networkError,
      );
    }

    final normalizedPath = normalizePath(path);
    final result = <FileEntry>[];

    for (final entry in _entries.values) {
      // Check if this entry is a direct child of the requested path
      if (entry.path == normalizedPath) continue;
      if (dirname(entry.path) != normalizedPath) continue;

      // Filter hidden files
      final showHidden = options?.showHidden ?? false;
      if (!showHidden) {
        if (entry.hidden || entry.name.startsWith('.')) continue;
      }

      result.add(entry);
    }

    // Sort by name
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  Future<List<FileEntry>> search(
    String path,
    String query, {
    bool recursive = false,
  }) async {
    final normalizedPath = normalizePath(path);
    final queryLower = query.toLowerCase();
    final result = <FileEntry>[];

    for (final entry in _entries.values) {
      if (entry.path == normalizedPath) continue;

      final isChild = recursive
          ? entry.path.startsWith('$normalizedPath/')
          : dirname(entry.path) == normalizedPath;

      if (!isChild) continue;
      if (entry.name.toLowerCase().contains(queryLower)) {
        result.add(entry);
      }
    }

    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  Future<FileEntry> stat(String path) async {
    final normalizedPath = normalizePath(path);
    final entry = _entries[normalizedPath];
    if (entry == null) {
      throw StorageException(
        'Not found',
        code: StorageException.notFound,
        path: path,
      );
    }
    return entry;
  }

  @override
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  }) async* {
    final normalizedPath = normalizePath(path);
    final content = _contents[normalizedPath];
    if (content == null) {
      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.failed,
        error: 'File not found: $path',
      );
      return;
    }

    final entry = _entries[normalizedPath];
    final totalBytes = content.length;

    yield TransferProgress(
      operation: TransferOperation.read,
      state: TransferState.inProgress,
      currentFile: entry,
      bytesTransferred: 0,
      totalBytes: totalBytes,
    );

    // Simulate chunked reading
    const chunkSize = 1024;
    var offset = 0;
    while (offset < totalBytes) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.read,
          state: TransferState.cancelled,
        );
        return;
      }

      final end = (offset + chunkSize > totalBytes)
          ? totalBytes
          : offset + chunkSize;
      offset = end;

      yield TransferProgress(
        operation: TransferOperation.read,
        state: TransferState.inProgress,
        currentFile: entry,
        bytesTransferred: offset,
        totalBytes: totalBytes,
      );
    }

    yield TransferProgress(
      operation: TransferOperation.read,
      state: TransferState.completed,
      currentFile: entry,
      bytesTransferred: totalBytes,
      totalBytes: totalBytes,
    );
  }

  @override
  Stream<TransferProgress> write(
    String path,
    Stream<List<int>> data, {
    CancelToken? cancelToken,
  }) async* {
    final normalizedPath = normalizePath(path);
    final buffer = <int>[];
    var bytesReceived = 0;

    await for (final chunk in data) {
      if (cancelToken?.isCancelled ?? false) {
        yield TransferProgress(
          operation: TransferOperation.write,
          state: TransferState.cancelled,
        );
        return;
      }
      buffer.addAll(chunk);
      bytesReceived += chunk.length;
      yield TransferProgress(
        operation: TransferOperation.write,
        state: TransferState.inProgress,
        bytesTransferred: bytesReceived,
      );
    }

    _contents[normalizedPath] = buffer;
    _entries[normalizedPath] = FileEntry(
      name: basename(normalizedPath),
      path: normalizedPath,
      isDirectory: false,
      size: buffer.length,
      modified: DateTime.now(),
    );

    yield TransferProgress(
      operation: TransferOperation.write,
      state: TransferState.completed,
      bytesTransferred: bytesReceived,
    );
  }

  @override
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options = const CopyOptions(),
    CancelToken? cancelToken,
  }) async* {
    final normalizedSource = normalizePath(sourcePath);
    final content = _contents[normalizedSource];
    if (content == null) {
      yield TransferProgress(
        operation: TransferOperation.copy,
        state: TransferState.failed,
        error: 'Source not found: $sourcePath',
      );
      return;
    }

    // For simplicity, if dest is also a mock, write directly
    if (destProvider is MockStorageProvider) {
      destProvider._contents[destPath] = List.from(content);
      destProvider._entries[destPath] = FileEntry(
        name: destProvider.basename(destPath),
        path: destPath,
        isDirectory: false,
        size: content.length,
        modified: DateTime.now(),
      );
    }

    yield TransferProgress(
      operation: TransferOperation.copy,
      state: TransferState.completed,
      bytesTransferred: content.length,
      totalBytes: content.length,
    );
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    final normalizedSource = normalizePath(sourcePath);
    final entry = _entries[normalizedSource];
    if (entry == null) {
      throw StorageException(
        'Not found',
        code: StorageException.notFound,
        path: sourcePath,
      );
    }

    _entries[destPath] = entry.copyWith(
      path: destPath,
      name: basename(destPath),
    );
    _contents[destPath] = _contents[normalizedSource] ?? [];
    _entries.remove(normalizedSource);
    _contents.remove(normalizedSource);
  }

  @override
  Future<void> rename(String path, String newName) async {
    final parent = dirname(path);
    final newPath = joinPath(parent, newName);
    await move(path, newPath);
  }

  @override
  Future<void> delete(String path) async {
    final normalizedPath = normalizePath(path);
    _entries.remove(normalizedPath);
    _contents.remove(normalizedPath);

    // Remove children if directory
    final children = _entries.keys
        .where(
          (k) =>
              k.startsWith('$normalizedPath/') || dirname(k) == normalizedPath,
        )
        .toList();
    for (final child in children) {
      _entries.remove(child);
      _contents.remove(child);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final normalizedPath = normalizePath(path);
    if (_entries.containsKey(normalizedPath)) {
      throw StorageException(
        'Already exists',
        code: StorageException.alreadyExists,
        path: path,
      );
    }
    _entries[normalizedPath] = FileEntry(
      name: basename(normalizedPath),
      path: normalizedPath,
      isDirectory: true,
      modified: DateTime.now(),
    );
  }

  @override
  Future<bool> exists(String path) async {
    return _entries.containsKey(normalizePath(path));
  }

  @override
  Future<String> get homePath async => '/';

  @override
  Future<DiskSpaceInfo> getDiskSpaceInfo(String path) async {
    return const DiskSpaceInfo(
      totalBytes: 2048 * 1024 * 1024,
      usedBytes: 1024 * 1024 * 1024,
      freeBytes: 1024 * 1024 * 1024,
    );
  }

  @override
  String normalizePath(String path) {
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    // Simple normalization: remove trailing slash, collapse double slashes
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  @override
  String joinPath(String parent, String child) {
    if (parent.endsWith('/')) return '$parent$child';
    return '$parent/$child';
  }

  @override
  String basename(String path) {
    final normalized = normalizePath(path);
    final parts = normalized.split('/');
    return parts.isEmpty || parts.last.isEmpty ? '/' : parts.last;
  }

  @override
  String dirname(String path) {
    final normalized = normalizePath(path);
    if (normalized == '/') return '/';
    final parts = normalized.split('/');
    if (parts.length <= 2) return '/';
    parts.removeLast();
    return parts.join('/');
  }

  @override
  bool supports(ProviderCapability capability) =>
      supportedCapabilities.contains(capability);

  /// Clear all entries (for test cleanup)
  void clear() {
    _entries.clear();
    _contents.clear();
  }
}
