// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_keys_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$apiKeysRepositoryHash() => r'2471f5d2793c4ea551499c967d101f5336581196';

/// Repository for managing cloud OAuth2 Client IDs and Secrets
///
/// Copied from [ApiKeysRepository].
@ProviderFor(ApiKeysRepository)
final apiKeysRepositoryProvider =
    NotifierProvider<
      ApiKeysRepository,
      Map<String, ApiKeyCredentials>
    >.internal(
      ApiKeysRepository.new,
      name: r'apiKeysRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$apiKeysRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ApiKeysRepository = Notifier<Map<String, ApiKeyCredentials>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
