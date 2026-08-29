import 'package:uuid/uuid.dart';

/// Type of storage provider / connection
enum ConnectionType {
  local,
  sftp,
  ftp,
  ftps,
  webdav,
  smb,
  gdrive,
  dropbox,
  onedrive,
  nextcloud;

  /// Whether this connection type requires a host
  bool get requiresHost {
    switch (this) {
      case ConnectionType.local:
      case ConnectionType.gdrive:
      case ConnectionType.dropbox:
      case ConnectionType.onedrive:
        return false;
      case ConnectionType.sftp:
      case ConnectionType.ftp:
      case ConnectionType.ftps:
      case ConnectionType.webdav:
      case ConnectionType.smb:
      case ConnectionType.nextcloud:
        return true;
    }
  }
}

/// Authentication method for a connection
enum AuthMethod {
  /// Username + password
  password,

  /// Private key (SFTP only)
  privateKey,

  /// OAuth2 (cloud providers)
  oauth2,

  /// Anonymous (FTP)
  anonymous,
}

/// A saved connection profile for remote/cloud storage.
///
/// Credentials are stored separately in the secure keyring, not in this model.
/// This model only holds non-sensitive connection metadata.
class ConnectionProfile {
  ConnectionProfile({
    required this.type,
    required this.name,
    this.host,
    this.port,
    this.username,
    this.authMethod = AuthMethod.password,
    this.defaultPath = '/',
    this.autoConnect = false,
    String? id,
    this.color,
    this.icon,
  }) : id = id ?? const Uuid().v4();

  /// Unique identifier
  final String id;

  /// Display name (e.g. "My NAS", "Work Server")
  final String name;

  /// Connection type
  final ConnectionType type;

  /// Hostname or IP address (null for local/cloud OAuth)
  final String? host;

  /// Port number (null = use protocol default)
  final int? port;

  /// Username (null for anonymous/OAuth)
  final String? username;

  /// Authentication method
  final AuthMethod authMethod;

  /// Default path to open when connecting
  final String defaultPath;

  /// Whether this connection should automatically connect on startup
  final bool autoConnect;

  /// Custom color for the connection icon (hex string)
  final String? color;

  /// Custom icon identifier
  final String? icon;

  /// Default port for this connection type
  int get defaultPort {
    switch (type) {
      case ConnectionType.sftp:
        return 22;
      case ConnectionType.ftp:
        return 21;
      case ConnectionType.ftps:
        return 990;
      case ConnectionType.webdav:
      case ConnectionType.nextcloud:
        return 443;
      case ConnectionType.smb:
        return 445;
      case ConnectionType.local:
      case ConnectionType.gdrive:
      case ConnectionType.dropbox:
      case ConnectionType.onedrive:
        return 0;
    }
  }

  /// Effective port (uses default if not specified)
  int get effectivePort => port ?? defaultPort;

  /// Whether this connection requires a host
  bool get requiresHost {
    switch (type) {
      case ConnectionType.local:
      case ConnectionType.gdrive:
      case ConnectionType.dropbox:
      case ConnectionType.onedrive:
        return false;
      case ConnectionType.sftp:
      case ConnectionType.ftp:
      case ConnectionType.ftps:
      case ConnectionType.webdav:
      case ConnectionType.smb:
      case ConnectionType.nextcloud:
        return true;
    }
  }

  /// Whether this connection uses OAuth2
  bool get isOAuth => authMethod == AuthMethod.oauth2;

  /// Key used to store/retrieve credentials from the secure keyring
  String get credentialKey => 'connection_$id';

  ConnectionProfile copyWith({
    String? id,
    String? name,
    ConnectionType? type,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? defaultPath,
    bool? autoConnect,
    String? color,
    String? icon,
  }) {
    return ConnectionProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      defaultPath: defaultPath ?? this.defaultPath,
      autoConnect: autoConnect ?? this.autoConnect,
      color: color ?? this.color,
      icon: icon ?? this.icon,
    );
  }

  @override
  String toString() =>
      'ConnectionProfile(id: $id, name: $name, type: $type, host: $host, port: $effectivePort, autoConnect: $autoConnect)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ConnectionProfile && id == other.id;

  @override
  int get hashCode => id.hashCode;
}