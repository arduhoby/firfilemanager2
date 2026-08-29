import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'models/connection_profile.dart';
import 'providers/ftp_provider.dart';
import 'providers/local_provider.dart';
import 'providers/sftp_provider.dart';
import 'providers/smb_provider.dart';
import 'providers/webdav_provider.dart';
import 'providers/cloud/google_drive_provider.dart';
import 'providers/cloud/dropbox_provider.dart';
import 'providers/cloud/onedrive_provider.dart';
import 'providers/cloud/nextcloud_provider.dart';
import 'storage_provider.dart';
import '../../features/settings/api_keys_repository.dart';
import '../settings/settings_provider.dart';

part 'storage_provider_service.g.dart';

/// Manages [StorageProvider] instances — one per connection profile.
///
/// This is the central registry for all active storage providers. The UI
/// requests a provider by profile ID (or 'local' for the local filesystem),
/// and this service returns the connected instance.
@Riverpod(keepAlive: true)
class StorageProviderRegistry extends _$StorageProviderRegistry {
  final _providers = <String, StorageProvider>{};

  @override
  Map<String, StorageProvider> build() {
    // Register the local provider immediately
    final local = LocalProvider();
    _providers['local'] = local;
    return Map.unmodifiable(_providers);
  }

  /// Get the local filesystem provider
  StorageProvider get local => _providers['local']!;

  /// Get a provider by ID
  StorageProvider? get(String id) => _providers[id];

  /// Register a new provider
  void register(String id, StorageProvider provider) {
    _providers[id] = provider;
    state = Map.unmodifiable(_providers);
  }

  /// Unregister and disconnect a provider
  Future<void> unregister(String id) async {
    final provider = _providers.remove(id);
    if (provider != null) {
      await provider.disconnect();
    }
    state = Map.unmodifiable(_providers);
  }

  /// Get or create a provider for a connection profile
  Future<StorageProvider> getOrCreate(
    ConnectionProfile profile, {
    String? password,
    String? privateKey,
    String? clientId,
    String? clientSecret,
  }) async {
    final existing = _providers[profile.id];
    if (existing != null && existing.isConnected) {
      return existing;
    }

    // Create new provider based on type
    final provider = _createProvider(
      profile,
      password: password,
      privateKey: privateKey,
      clientId: clientId,
      clientSecret: clientSecret,
    );
    await provider.connect();
    _providers[profile.id] = provider;
    state = Map.unmodifiable(_providers);
    return provider;
  }

  StorageProvider _createProvider(
    ConnectionProfile profile, {
    String? password,
    String? privateKey,
    String? clientId,
    String? clientSecret,
  }) {
    switch (profile.type) {
      case ConnectionType.local:
        return LocalProvider();
      case ConnectionType.sftp:
        return SftpProvider(
          profile: profile,
          password: password,
          privateKey: privateKey,
        );
      case ConnectionType.ftp:
      case ConnectionType.ftps:
        return FtpProvider(profile: profile, password: password);
      case ConnectionType.webdav:
        return WebdavProvider(
          profile: profile,
          password: password,
          chunkSizeBytes: () =>
              ref.read(settingsProvider).filePartSizeMb * 1024 * 1024,
        );
      case ConnectionType.smb:
        return SmbProvider(profile: profile, password: password);
      case ConnectionType.gdrive:
        final hasProfileKeys = clientId != null && clientId.isNotEmpty;
        final keys = hasProfileKeys
            ? null
            : ref.read(apiKeysRepositoryProvider.notifier).getKeys('gdrive');
        return GoogleDriveProvider(
          profile: profile,
          clientId: hasProfileKeys ? clientId : keys?.clientId,
          clientSecret: hasProfileKeys ? clientSecret : keys?.clientSecret,
        );
      case ConnectionType.dropbox:
        final hasProfileKeys = clientId != null && clientId.isNotEmpty;
        final keys = hasProfileKeys
            ? null
            : ref.read(apiKeysRepositoryProvider.notifier).getKeys('dropbox');
        return DropboxProvider(
          profile,
          clientId: hasProfileKeys ? clientId : keys?.clientId,
          clientSecret: hasProfileKeys ? clientSecret : keys?.clientSecret,
        );
      case ConnectionType.onedrive:
        final hasProfileKeys = clientId != null && clientId.isNotEmpty;
        final keys = hasProfileKeys
            ? null
            : ref.read(apiKeysRepositoryProvider.notifier).getKeys('onedrive');
        return OneDriveProvider(
          profile,
          clientId: hasProfileKeys ? clientId : keys?.clientId,
          clientSecret: hasProfileKeys ? clientSecret : keys?.clientSecret,
        );
      case ConnectionType.nextcloud:
        return NextcloudProvider(profile, password: password);
    }
  }
}

/// Convenience provider to get the local storage provider
@Riverpod(keepAlive: true)
StorageProvider localStorageProvider(LocalStorageProviderRef ref) {
  return ref
      .watch(storageProviderRegistryProvider)
      .values
      .firstWhere((p) => p.profile == null, orElse: () => LocalProvider());
}
