// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_provider_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$localStorageProviderHash() =>
    r'e2ee6eccb46a43ef8e13db4a10af9a67724cfaba';

/// Convenience provider to get the local storage provider
///
/// Copied from [localStorageProvider].
@ProviderFor(localStorageProvider)
final localStorageProviderProvider = Provider<StorageProvider>.internal(
  localStorageProvider,
  name: r'localStorageProviderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$localStorageProviderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LocalStorageProviderRef = ProviderRef<StorageProvider>;
String _$storageProviderRegistryHash() =>
    r'f954243302a552c10736346fd79fa43faaf4098e';

/// Manages [StorageProvider] instances — one per connection profile.
///
/// This is the central registry for all active storage providers. The UI
/// requests a provider by profile ID (or 'local' for the local filesystem),
/// and this service returns the connected instance.
///
/// Copied from [StorageProviderRegistry].
@ProviderFor(StorageProviderRegistry)
final storageProviderRegistryProvider =
    NotifierProvider<
      StorageProviderRegistry,
      Map<String, StorageProvider>
    >.internal(
      StorageProviderRegistry.new,
      name: r'storageProviderRegistryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$storageProviderRegistryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$StorageProviderRegistry = Notifier<Map<String, StorageProvider>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
