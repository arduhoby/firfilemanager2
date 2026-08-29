import 'package:path/path.dart' as p;

/// Represents a file or directory entry in any storage provider.
///
/// This is the unified model used across all providers (local, SFTP, FTP,
/// WebDAV, SMB, cloud). UI never needs to know which protocol produced it.
class FileEntry {
  FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modified,
    this.permissions,
    this.owner,
    this.group,
    this.mimeType,
    this.hidden = false,
    this.symlink = false,
    this.symlinkTarget,
    this.isShared = false,
  });

  /// Display name (e.g. "Documents")
  final String name;

  /// Full path within the provider's namespace (e.g. "/home/user/Documents")
  final String path;

  /// Whether this entry is a directory
  final bool isDirectory;

  /// Size in bytes (0 for directories)
  final int size;

  /// Last modified date
  final DateTime? modified;

  /// Unix-style permission string (e.g. "rwxr-xr-x") or null if not available
  final String? permissions;

  /// Owner name (Unix/SFTP) or null
  final String? owner;

  /// Group name (Unix/SFTP) or null
  final String? group;

  /// MIME type (e.g. "image/png") or null if unknown
  final String? mimeType;

  /// Whether this is a hidden file (starts with . on Unix)
  final bool hidden;

  /// Whether this is a symbolic link
  final bool symlink;

  /// Target path if this is a symlink, null otherwise
  final String? symlinkTarget;

  /// Whether this path is shared via SMB
  final bool isShared;

  /// File extension (e.g. "txt", "png") or empty string if none
  String get extension {
    if (isDirectory) return '';
    return p.extension(name).toLowerCase().replaceFirst('.', '');
  }

  /// Parent directory path
  String get parentPath => p.dirname(path);

  /// Whether this is the root of the provider's namespace
  bool get isRoot => path == '/' || path == '';

  /// Create a copy with updated fields
  FileEntry copyWith({
    String? name,
    String? path,
    bool? isDirectory,
    int? size,
    DateTime? modified,
    String? permissions,
    String? owner,
    String? group,
    String? mimeType,
    bool? hidden,
    bool? symlink,
    String? symlinkTarget,
    bool? isShared,
  }) {
    return FileEntry(
      name: name ?? this.name,
      path: path ?? this.path,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      permissions: permissions ?? this.permissions,
      owner: owner ?? this.owner,
      group: group ?? this.group,
      mimeType: mimeType ?? this.mimeType,
      hidden: hidden ?? this.hidden,
      symlink: symlink ?? this.symlink,
      symlinkTarget: symlinkTarget ?? this.symlinkTarget,
      isShared: isShared ?? this.isShared,
    );
  }

  @override
  String toString() => 'FileEntry(name: $name, path: $path, isDir: $isDirectory, size: $size)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileEntry && runtimeType == other.runtimeType && path == other.path && name == other.name;

  @override
  int get hashCode => path.hashCode ^ name.hashCode;
}