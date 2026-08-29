import '../../core/storage/models/file_entry.dart';

enum SyncStatus { missing, modified, identical, inaccessible }

class SyncItem {
  SyncItem({
    required this.sourceEntry,
    required this.relativePath,
    required this.depth,
    required this.status,
    required this.isSelected,
    this.destinationEntry,
    this.comparisonReason,
    this.error,
  });

  final FileEntry sourceEntry;
  final FileEntry? destinationEntry;
  final String relativePath;
  final int depth;
  final SyncStatus status;
  bool isSelected;
  final String? comparisonReason;
  final String? error;

  bool get canSelect => status != SyncStatus.inaccessible;

  SyncItem copyWith({bool? isSelected}) => SyncItem(
    sourceEntry: sourceEntry,
    destinationEntry: destinationEntry,
    relativePath: relativePath,
    depth: depth,
    status: status,
    isSelected: isSelected ?? this.isSelected,
    comparisonReason: comparisonReason,
    error: error,
  );
}

class SyncSelectionPolicy {
  const SyncSelectionPolicy({
    this.missing = true,
    this.modified = true,
    this.identical = false,
  });

  final bool missing;
  SyncSelectionPolicy copyWith({
    bool? missing,
    bool? modified,
    bool? identical,
  }) => SyncSelectionPolicy(
    missing: missing ?? this.missing,
    modified: modified ?? this.modified,
    identical: identical ?? this.identical,
  );
  final bool modified;
  final bool identical;

  bool selects(SyncStatus status) => switch (status) {
    SyncStatus.missing => missing,
    SyncStatus.modified => modified,
    SyncStatus.identical => identical,
    SyncStatus.inaccessible => false,
  };

  Map<String, dynamic> toJson() => {
    'missing': missing,
    'modified': modified,
    'identical': identical,
  };

  factory SyncSelectionPolicy.fromJson(Map<String, dynamic> json) =>
      SyncSelectionPolicy(
        missing: json['missing'] as bool? ?? true,
        modified: json['modified'] as bool? ?? true,
        identical: json['identical'] as bool? ?? false,
      );
}

class SyncPreviewSelection {
  const SyncPreviewSelection({
    required this.selectedItems,
    required this.policy,
    required this.includedPaths,
    required this.excludedPaths,
  });

  final List<SyncItem> selectedItems;
  final SyncSelectionPolicy policy;
  final Set<String> includedPaths;
  final Set<String> excludedPaths;
}

class SyncFileFailure {
  const SyncFileFailure({required this.relativePath, required this.message});

  final String relativePath;
  final String message;

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'message': message,
  };

  factory SyncFileFailure.fromJson(Map<String, dynamic> json) =>
      SyncFileFailure(
        relativePath: json['relativePath'] as String,
        message: json['message'] as String,
      );
}

class SyncExecutionResult {
  const SyncExecutionResult({
    required this.createdFiles,
    required this.updatedFiles,
    required this.failedFiles,
    required this.cancelled,
    this.transferredBytes = 0,
    this.failures = const [],
  });

  final int createdFiles;
  final int updatedFiles;
  final int failedFiles;
  final bool cancelled;
  final int transferredBytes;
  final List<SyncFileFailure> failures;

  int get successfulFiles => createdFiles + updatedFiles;
}
