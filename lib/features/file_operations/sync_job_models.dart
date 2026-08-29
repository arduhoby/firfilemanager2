import 'sync_models.dart';

enum SyncScheduleType { manual, once, daily, weekly }

enum SyncMissedRunPolicy { skip, runWhenAvailable }

enum SyncRunTrigger { manual, scheduled, commandLine }

enum SyncRunOutcome { success, partialFailure, failed, cancelled }

class SyncEndpoint {
  const SyncEndpoint({
    required this.providerId,
    required this.path,
    required this.displayName,
    this.documentTreeUri,
    this.volumeIdentity,
  });

  final String providerId;
  final String path;
  final String displayName;
  final String? documentTreeUri;
  final String? volumeIdentity;

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'path': path,
    'displayName': displayName,
    if (documentTreeUri != null) 'documentTreeUri': documentTreeUri,
    if (volumeIdentity != null) 'volumeIdentity': volumeIdentity,
  };

  factory SyncEndpoint.fromJson(Map<String, dynamic> json) => SyncEndpoint(
    providerId: json['providerId'] as String? ?? 'local',
    path: json['path'] as String,
    displayName: json['displayName'] as String? ?? json['path'] as String,
    documentTreeUri: json['documentTreeUri'] as String?,
    volumeIdentity: json['volumeIdentity'] as String?,
  );
}

class SyncSchedule {
  const SyncSchedule({
    this.type = SyncScheduleType.manual,
    this.hour = 0,
    this.minute = 0,
    this.weekdays = const {DateTime.monday},
    this.onceAt,
    this.missedRunPolicy = SyncMissedRunPolicy.runWhenAvailable,
    this.requireWifi = false,
    this.allowMobileData = false,
    this.requireCharging = false,
  });

  final SyncScheduleType type;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final DateTime? onceAt;
  final SyncMissedRunPolicy missedRunPolicy;
  final bool requireWifi;
  final bool allowMobileData;
  final bool requireCharging;

  bool get isScheduled => type != SyncScheduleType.manual;

  DateTime? nextOccurrence(DateTime after) {
    switch (type) {
      case SyncScheduleType.manual:
        return null;
      case SyncScheduleType.once:
        final value = onceAt;
        return value != null && value.isAfter(after) ? value : null;
      case SyncScheduleType.daily:
        var candidate = DateTime(
          after.year,
          after.month,
          after.day,
          hour,
          minute,
        );
        if (!candidate.isAfter(after)) {
          candidate = DateTime(
            after.year,
            after.month,
            after.day + 1,
            hour,
            minute,
          );
        }
        return candidate;
      case SyncScheduleType.weekly:
        if (weekdays.isEmpty) return null;
        for (var offset = 0; offset <= 7; offset++) {
          final day = DateTime(after.year, after.month, after.day + offset);
          if (!weekdays.contains(day.weekday)) continue;
          final candidate = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          );
          if (candidate.isAfter(after)) return candidate;
        }
        return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays.toList()..sort(),
    if (onceAt != null) 'onceAt': onceAt!.toIso8601String(),
    'missedRunPolicy': missedRunPolicy.name,
    'requireWifi': requireWifi,
    'allowMobileData': allowMobileData,
    'requireCharging': requireCharging,
  };

  factory SyncSchedule.fromJson(Map<String, dynamic> json) => SyncSchedule(
    type: SyncScheduleType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => SyncScheduleType.manual,
    ),
    hour: json['hour'] as int? ?? 0,
    minute: json['minute'] as int? ?? 0,
    weekdays: ((json['weekdays'] as List?) ?? const [DateTime.monday])
        .whereType<num>()
        .map((value) => value.toInt())
        .toSet(),
    onceAt: DateTime.tryParse(json['onceAt'] as String? ?? ''),
    missedRunPolicy: SyncMissedRunPolicy.values.firstWhere(
      (value) => value.name == json['missedRunPolicy'],
      orElse: () => SyncMissedRunPolicy.runWhenAvailable,
    ),
    requireWifi: json['requireWifi'] as bool? ?? false,
    allowMobileData: json['allowMobileData'] as bool? ?? false,
    requireCharging: json['requireCharging'] as bool? ?? false,
  );
}

class SyncJob {
  const SyncJob({
    required this.id,
    required this.name,
    required this.source,
    required this.destination,
    required this.selectionPolicy,
    required this.includedPaths,
    required this.excludedPaths,
    required this.schedule,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.lastRunAt,
    this.lastOutcome,
  });

  static const schemaVersion = 1;

  final String id;
  final String name;
  final SyncEndpoint source;
  final SyncEndpoint destination;
  final SyncSelectionPolicy selectionPolicy;
  final Set<String> includedPaths;
  final Set<String> excludedPaths;
  final SyncSchedule schedule;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final SyncRunOutcome? lastOutcome;

  DateTime? get nextRunAt =>
      enabled ? schedule.nextOccurrence(DateTime.now()) : null;

  SyncJob copyWith({
    String? name,
    SyncEndpoint? source,
    SyncEndpoint? destination,
    SyncSelectionPolicy? selectionPolicy,
    Set<String>? includedPaths,
    Set<String>? excludedPaths,
    SyncSchedule? schedule,
    bool? enabled,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    SyncRunOutcome? lastOutcome,
  }) => SyncJob(
    id: id,
    name: name ?? this.name,
    source: source ?? this.source,
    destination: destination ?? this.destination,
    selectionPolicy: selectionPolicy ?? this.selectionPolicy,
    includedPaths: includedPaths ?? this.includedPaths,
    excludedPaths: excludedPaths ?? this.excludedPaths,
    schedule: schedule ?? this.schedule,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    lastOutcome: lastOutcome ?? this.lastOutcome,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'source': source.toJson(),
    'destination': destination.toJson(),
    'selectionPolicy': selectionPolicy.toJson(),
    'includedPaths': includedPaths.toList()..sort(),
    'excludedPaths': excludedPaths.toList()..sort(),
    'schedule': schedule.toJson(),
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (lastRunAt != null) 'lastRunAt': lastRunAt!.toIso8601String(),
    if (lastOutcome != null) 'lastOutcome': lastOutcome!.name,
  };

  factory SyncJob.fromJson(Map<String, dynamic> json) => SyncJob(
    id: json['id'] as String,
    name: json['name'] as String,
    source: SyncEndpoint.fromJson(json['source'] as Map<String, dynamic>),
    destination: SyncEndpoint.fromJson(
      json['destination'] as Map<String, dynamic>,
    ),
    selectionPolicy: SyncSelectionPolicy.fromJson(
      json['selectionPolicy'] as Map<String, dynamic>? ?? const {},
    ),
    includedPaths: ((json['includedPaths'] as List?) ?? const [])
        .whereType<String>()
        .toSet(),
    excludedPaths: ((json['excludedPaths'] as List?) ?? const [])
        .whereType<String>()
        .toSet(),
    schedule: SyncSchedule.fromJson(
      json['schedule'] as Map<String, dynamic>? ?? const {},
    ),
    enabled: json['enabled'] as bool? ?? true,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    lastRunAt: DateTime.tryParse(json['lastRunAt'] as String? ?? ''),
    lastOutcome: json['lastOutcome'] == null
        ? null
        : SyncRunOutcome.values.firstWhere(
            (value) => value.name == json['lastOutcome'],
            orElse: () => SyncRunOutcome.failed,
          ),
  );
}

class SyncRunReport {
  const SyncRunReport({
    required this.id,
    required this.jobId,
    required this.jobName,
    required this.trigger,
    required this.startedAt,
    required this.completedAt,
    required this.outcome,
    required this.scannedFiles,
    required this.selectedFiles,
    required this.createdFiles,
    required this.updatedFiles,
    required this.failedFiles,
    required this.transferredBytes,
    required this.failures,
  });

  final String id;
  final String jobId;
  final String jobName;
  final SyncRunTrigger trigger;
  final DateTime startedAt;
  final DateTime completedAt;
  final SyncRunOutcome outcome;
  final int scannedFiles;
  final int selectedFiles;
  final int createdFiles;
  final int updatedFiles;
  final int failedFiles;
  final int transferredBytes;
  final List<SyncFileFailure> failures;

  Duration get duration => completedAt.difference(startedAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobId': jobId,
    'jobName': jobName,
    'trigger': trigger.name,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'outcome': outcome.name,
    'scannedFiles': scannedFiles,
    'selectedFiles': selectedFiles,
    'createdFiles': createdFiles,
    'updatedFiles': updatedFiles,
    'failedFiles': failedFiles,
    'transferredBytes': transferredBytes,
    'failures': failures.map((failure) => failure.toJson()).toList(),
  };

  factory SyncRunReport.fromJson(Map<String, dynamic> json) => SyncRunReport(
    id: json['id'] as String,
    jobId: json['jobId'] as String,
    jobName: json['jobName'] as String,
    trigger: SyncRunTrigger.values.firstWhere(
      (value) => value.name == json['trigger'],
      orElse: () => SyncRunTrigger.manual,
    ),
    startedAt: DateTime.parse(json['startedAt'] as String),
    completedAt: DateTime.parse(json['completedAt'] as String),
    outcome: SyncRunOutcome.values.firstWhere(
      (value) => value.name == json['outcome'],
      orElse: () => SyncRunOutcome.failed,
    ),
    scannedFiles: json['scannedFiles'] as int? ?? 0,
    selectedFiles: json['selectedFiles'] as int? ?? 0,
    createdFiles: json['createdFiles'] as int? ?? 0,
    updatedFiles: json['updatedFiles'] as int? ?? 0,
    failedFiles: json['failedFiles'] as int? ?? 0,
    transferredBytes: json['transferredBytes'] as int? ?? 0,
    failures: ((json['failures'] as List?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(
          (value) => SyncFileFailure.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList(),
  );
}
