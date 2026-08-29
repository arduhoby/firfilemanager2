import 'dart:async';

import 'models/connection_profile.dart';
import 'models/file_entry.dart';
import 'models/transfer_progress.dart';

/// Information about disk space usage
class DiskSpaceInfo {
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;

  const DiskSpaceInfo({
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
  });
}

/// Exception thrown by storage providers for operation errors.
class StorageException implements Exception {
  StorageException(this.message, {this.code, this.path, this.cause});

  /// Human-readable error message
  final String message;

  /// Error code (e.g. 'ACCESS_DENIED', 'NOT_FOUND', 'ALREADY_EXISTS')
  final String? code;

  /// Path that caused the error, if applicable
  final String? path;

  /// Underlying cause, if any
  final Object? cause;

  /// Common error codes
  static const String accessDenied = 'ACCESS_DENIED';
  static const String notFound = 'NOT_FOUND';
  static const String alreadyExists = 'ALREADY_EXISTS';
  static const String networkError = 'NETWORK_ERROR';
  static const String timeout = 'TIMEOUT';
  static const String authenticationFailed = 'AUTH_FAILED';
  static const String cancelled = 'CANCELLED';
  static const String notSupported = 'NOT_SUPPORTED';

  @override
  String toString() => 'StorageException($code: $message${path != null ? ' at $path' : ''})';
}

/// Options for listing directory contents
class ListOptions {
  const ListOptions({
    this.showHidden = false,
    this.includeMetadata = true,
  });

  /// Whether to include hidden files (dotfiles on Unix)
  final bool showHidden;

  /// Whether to fetch full metadata (permissions, owner, etc.)
  /// Some providers may skip metadata for performance
  final bool includeMetadata;
}

/// Options for copy/move operations
class CopyOptions {
  const CopyOptions({
    this.overwrite = false,
    this.mergeDirectories = true,
    this.preservePermissions = true,
  });

  /// Whether to overwrite existing files at the destination
  final bool overwrite;

  /// Whether to merge directory contents if destination exists
  final bool mergeDirectories;

  /// Whether to preserve source permissions on the destination
  final bool preservePermissions;
}

/// The core abstraction for all storage providers.
///
/// Every storage backend (local filesystem, SFTP, FTP, WebDAV, SMB, cloud)
/// implements this interface. The UI layer interacts with files exclusively
/// through this interface, never knowing which protocol is underneath.
///
/// All methods are async and may throw [StorageException].
/// Transfer methods ([read], [write], [copy]) return a [Stream<TransferProgress>]
/// that emits progress updates and can be cancelled via [CancelToken].
abstract interface class StorageProvider {
  /// The connection profile backing this provider, or null for local
  ConnectionProfile? get profile;

  /// Human-readable name for this provider (e.g. "Local", "SFTP: My Server")
  String get displayName;

  /// Whether this provider is currently connected/available
  bool get isConnected;

  /// Stream that emits connection state changes
  Stream<bool> get connectionStateChanges;

  /// Connect/authenticate using the profile's credentials
  ///
  /// For local providers this is a no-op. For remote providers, this
  /// establishes the connection. Throws [StorageException] on failure.
  Future<void> connect();

  /// Disconnect and release resources
  Future<void> disconnect();

  /// List directory contents
  ///
  /// Returns a list of [FileEntry] for the given [path].
  /// Throws [StorageException] if the path doesn't exist or access is denied.
  Future<List<FileEntry>> list(String path, [ListOptions? options]);

  /// Get metadata for a single file/directory
  ///
  /// Returns the [FileEntry] for [path], or throws [StorageException]
  /// if it doesn't exist.
  Future<FileEntry> stat(String path);

  /// Read a file's contents as a stream of bytes
  ///
  /// Emits [TransferProgress] updates as data is read. The caller is
  /// responsible for writing the data to the destination.
  /// Use [cancelToken] to abort the operation.
  Stream<TransferProgress> read(
    String path, {
    CancelToken? cancelToken,
  });

  /// Write data to a file
  ///
  /// Emits [TransferProgress] updates as data is written.
  /// Use [cancelToken] to abort the operation.
  Stream<TransferProgress> write(
    String path,
    Stream<List<int>> data, {
    CancelToken? cancelToken,
  });

  /// Copy a file or directory to another location
  ///
  /// If [destProvider] is the same as this provider, the copy is done
  /// within the same storage. If different, data is streamed across providers.
  /// Emits [TransferProgress] updates. Use [cancelToken] to abort.
  Stream<TransferProgress> copy(
    String sourcePath,
    StorageProvider destProvider,
    String destPath, {
    CopyOptions options,
    CancelToken? cancelToken,
  });

  /// Move/rename a file or directory within this provider
  ///
  /// For cross-provider moves, use [copy] + [delete].
  /// Throws [StorageException] if cross-provider move is attempted.
  Future<void> move(String sourcePath, String destPath);

  /// Rename a file or directory
  ///
  /// This is a convenience method equivalent to [move] within the same
  /// parent directory.
  Future<void> rename(String path, String newName);

  /// Delete a file or directory
  ///
  /// If [path] is a directory, it is deleted recursively.
  /// Throws [StorageException] if the path doesn't exist or access is denied.
  Future<void> delete(String path);

  /// Create a directory
  ///
  /// Creates [path] and any necessary parent directories.
  /// Throws [StorageException] if the directory already exists.
  Future<void> mkdir(String path);

  /// Check if a path exists
  Future<bool> exists(String path);

  /// Get the home/root path for this provider
  ///
  /// For local providers, this is the user's home directory.
  /// For remote providers, this is the default path from the profile.
  Future<String> get homePath;

  /// Get total, free and used space at the given path
  ///
  /// Returns null if the provider doesn't support this.
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path);

  /// Normalize a path for this provider
  ///
  /// Handles path separators, resolves . and .., etc.
  String normalizePath(String path);

  /// Join path components
  String joinPath(String parent, String child);

  /// Get the basename (last component) of a path
  String basename(String path);

  /// Get the dirname (parent) of a path
  String dirname(String path);

  /// Search files/folders under the given [path] matching [query].
  ///
  /// Returns a list of [FileEntry] matching the query.
  /// If [recursive] is true, searches subdirectories recursively.
  Future<List<FileEntry>> search(String path, String query, {bool recursive = false});

  /// Whether this provider supports the given operation
  ///
  /// Some providers may not support all operations (e.g. cloud providers
  /// may not support [getFreeSpace] or [move] across directories).
  bool supports(ProviderCapability capability);
}

/// Capabilities that a provider may or may not support
enum ProviderCapability {
  /// Can read file contents
  read,

  /// Can write file contents
  write,

  /// Can delete files
  delete,

  /// Can move/rename within the provider
  move,

  /// Can create directories
  mkdir,

  /// Can list directory contents
  list,

  /// Can get free space
  freeSpace,

  /// Supports symbolic links
  symlinks,

  /// Supports permission management
  permissions,

  /// Supports streaming (chunked) transfers
  streaming,

  /// Can search files/directories
  search,
}