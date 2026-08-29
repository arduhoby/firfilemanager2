// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_operations_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$fileOperationsServiceHash() =>
    r'21d5aa1674bb7b28861bea7e015315f6f6ae6190';

/// Service that executes file operations (copy, move, delete, rename, mkdir)
/// and updates the [OperationProgress] state.
///
/// All operations are async and report progress via [OperationProgress] provider.
/// Operations can be cancelled via [CancelToken].
///
/// Copied from [FileOperationsService].
@ProviderFor(FileOperationsService)
final fileOperationsServiceProvider =
    NotifierProvider<FileOperationsService, void>.internal(
      FileOperationsService.new,
      name: r'fileOperationsServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$fileOperationsServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$FileOperationsService = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
