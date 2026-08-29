// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recent_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$recentServiceHash() => r'1ff8471f12506396aec283d376582f6610a42edb';

/// Service to manage recent apps, folders, and files.
///
/// Copied from [RecentService].
@ProviderFor(RecentService)
final recentServiceProvider =
    NotifierProvider<RecentService, RecentState>.internal(
      RecentService.new,
      name: r'recentServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$recentServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$RecentService = Notifier<RecentState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
