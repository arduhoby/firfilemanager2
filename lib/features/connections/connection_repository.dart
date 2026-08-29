import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/storage/models/connection_profile.dart';
import '../../core/storage/storage_provider_service.dart';

part 'connection_repository.g.dart';

/// Repository for managing saved connection profiles.
///
/// Connection metadata (name, host, port, type) is stored in memory.
/// Credentials (passwords, private keys) are stored in [FlutterSecureStorage]
/// using the platform keychain/keystore.
@Riverpod(keepAlive: true)
class ConnectionRepository extends _$ConnectionRepository {
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final Completer<void> _loaded = Completer<void>();

  @override
  List<ConnectionProfile> build() {
    unawaited(_loadConnections());
    return [];
  }

  Future<void> get loaded => _loaded.future;

  Future<void> _loadConnections() async {
    try {
      final json = await _secureStorage.read(key: 'connections');
      if (json != null) {
        final list = (jsonDecode(json) as List)
            .whereType<Map<Object?, Object?>>()
            .map(Map<String, dynamic>.from);
        state = list
            .map(
              (e) => ConnectionProfile(
                id: e['id'] as String,
                name: e['name'] as String,
                type: ConnectionType.values.firstWhere(
                  (t) => t.name == e['type'],
                  orElse: () => ConnectionType.sftp,
                ),
                host: e['host'] as String?,
                port: e['port'] as int?,
                username: e['username'] as String?,
                authMethod: AuthMethod.values.firstWhere(
                  (a) => a.name == e['authMethod'],
                  orElse: () => AuthMethod.password,
                ),
                defaultPath: e['defaultPath'] as String? ?? '/',
                autoConnect: e['autoConnect'] as bool? ?? false,
              ),
            )
            .toList();

        unawaited(
          Future.microtask(() async {
            final registry = ref.read(storageProviderRegistryProvider.notifier);
            for (final profile in state) {
              if (profile.autoConnect) {
                try {
                  final password = await getPassword(profile.id);
                  final key = await getPrivateKey(profile.id);
                  final clientId = await getClientId(profile.id);
                  final clientSecret = await getClientSecret(profile.id);
                  await registry.getOrCreate(
                    profile,
                    password: password,
                    privateKey: key,
                    clientId: clientId,
                    clientSecret: clientSecret,
                  );
                } catch (_) {
                  // A saved profile stays available when auto-connect fails.
                }
              }
            }
          }),
        );
      }
    } catch (_) {
      state = const [];
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> saveConnections() async {
    try {
      final json = jsonEncode(
        state
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'type': p.type.name,
                'host': p.host,
                'port': p.port,
                'username': p.username,
                'authMethod': p.authMethod.name,
                'defaultPath': p.defaultPath,
                'autoConnect': p.autoConnect,
              },
            )
            .toList(),
      );
      await _secureStorage.write(key: 'connections', value: json);
    } catch (e) {
      // Ignore storage errors — connections stay in memory
    }
  }

  // Memory fallback map
  final _memoryCredentials = <String, String>{};

  Future<File> _getFallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'credentials_fallback.json'));
  }

  Future<void> _writeCredential(String key, String value) async {
    _memoryCredentials[key] = value;
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {
      try {
        final file = await _getFallbackFile();
        final Map<String, dynamic> data = file.existsSync()
            ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
            : {};
        data[key] = value;
        file.writeAsStringSync(jsonEncode(data));
      } catch (_) {}
    }
  }

  Future<String?> _readCredential(String key) async {
    if (_memoryCredentials.containsKey(key)) {
      return _memoryCredentials[key];
    }
    try {
      final val = await _secureStorage.read(key: key);
      if (val != null) {
        _memoryCredentials[key] = val;
        return val;
      }
    } catch (_) {}

    try {
      final file = await _getFallbackFile();
      if (file.existsSync()) {
        final Map<String, dynamic> data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        if (data.containsKey(key)) {
          final val = data[key] as String?;
          if (val != null) {
            _memoryCredentials[key] = val;
            return val;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _deleteCredential(String key) async {
    _memoryCredentials.remove(key);
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
    try {
      final file = await _getFallbackFile();
      if (file.existsSync()) {
        final Map<String, dynamic> data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        data.remove(key);
        file.writeAsStringSync(jsonEncode(data));
      }
    } catch (_) {}
  }

  /// Add a new connection profile
  Future<void> addConnection(
    ConnectionProfile profile, {
    String? password,
    String? privateKey,
    String? clientId,
    String? clientSecret,
  }) async {
    state = [...state, profile];
    await saveConnections();

    if (password != null) {
      await _writeCredential(profile.credentialKey, password);
    }
    if (privateKey != null) {
      await _writeCredential('${profile.credentialKey}_key', privateKey);
    }
    if (clientId != null && clientId.isNotEmpty) {
      await _writeCredential('${profile.credentialKey}_client_id', clientId);
    }
    if (clientSecret != null && clientSecret.isNotEmpty) {
      await _writeCredential(
        '${profile.credentialKey}_client_secret',
        clientSecret,
      );
    }
  }

  /// Update an existing connection profile
  Future<void> updateConnection(
    ConnectionProfile profile, {
    String? password,
    String? privateKey,
    String? clientId,
    String? clientSecret,
  }) async {
    state = state.map((p) => p.id == profile.id ? profile : p).toList();
    await saveConnections();

    if (password != null) {
      await _writeCredential(profile.credentialKey, password);
    }
    if (privateKey != null) {
      await _writeCredential('${profile.credentialKey}_key', privateKey);
    }
    if (clientId != null) {
      await _writeCredential('${profile.credentialKey}_client_id', clientId);
    }
    if (clientSecret != null) {
      await _writeCredential(
        '${profile.credentialKey}_client_secret',
        clientSecret,
      );
    }
  }

  /// Delete a connection profile
  Future<void> deleteConnection(String id) async {
    final profile = state.where((p) => p.id == id).firstOrNull;
    state = state.where((p) => p.id != id).toList();
    await saveConnections();

    if (profile != null) {
      await _deleteCredential(profile.credentialKey);
      await _deleteCredential('${profile.credentialKey}_key');
      await _deleteCredential('${profile.credentialKey}_client_id');
      await _deleteCredential('${profile.credentialKey}_client_secret');
    }
  }

  /// Get saved password for a connection
  Future<String?> getPassword(String connectionId) async {
    return await _readCredential('connection_$connectionId');
  }

  /// Get saved private key for a connection
  Future<String?> getPrivateKey(String connectionId) async {
    return await _readCredential('connection_${connectionId}_key');
  }

  /// Get saved Client ID for a connection
  Future<String?> getClientId(String connectionId) async {
    return await _readCredential('connection_${connectionId}_client_id');
  }

  /// Get saved Client Secret for a connection
  Future<String?> getClientSecret(String connectionId) async {
    return await _readCredential('connection_${connectionId}_client_secret');
  }

  /// Get a connection by ID
  ConnectionProfile? getById(String id) {
    return state.where((p) => p.id == id).firstOrNull;
  }
}
