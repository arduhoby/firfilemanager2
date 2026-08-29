// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_operations_actions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$fileOperationsActionsHash() =>
    r'aaad53ce7699325362e5ff333ca69d9786b81dfe';

/// Actions provider that bridges UI interactions (context menu, dialogs)
/// with the [FileOperationsService].
///
/// Handles clipboard operations, rename/delete/new folder dialogs,
/// and properties display.
///
/// Copied from [FileOperationsActions].
@ProviderFor(FileOperationsActions)
final fileOperationsActionsProvider =
    NotifierProvider<FileOperationsActions, void>.internal(
      FileOperationsActions.new,
      name: r'fileOperationsActionsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$fileOperationsActionsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$FileOperationsActions = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
