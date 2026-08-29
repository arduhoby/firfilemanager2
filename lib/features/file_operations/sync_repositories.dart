import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/app_preferences.dart';
import 'sync_job_models.dart';
import 'sync_models.dart';

part 'sync_repositories.g.dart';

const _syncJobsKey = 'fir_sync_jobs_v1';
const _syncHistoryKey = 'fir_sync_run_history_v1';
const _maximumHistoryEntries = 100;

class SyncJobNameConflict implements Exception {
  const SyncJobNameConflict(this.name);

  final String name;

  @override
  String toString() => 'A synchronization job named "$name" already exists.';
}

@Riverpod(keepAlive: true)
class SyncJobRepository extends _$SyncJobRepository {
  final Completer<void> _loaded = Completer<void>();

  @override
  List<SyncJob> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> get loaded => _loaded.future;

  Future<void> _load() async {
    try {
      final preferences = await AppPreferences.getInstance();
      final encodedJobs = preferences.getStringList(_syncJobsKey) ?? const [];
      final jobs = <SyncJob>[];
      for (final encoded in encodedJobs) {
        try {
          jobs.add(
            SyncJob.fromJson(
              Map<String, dynamic>.from(jsonDecode(encoded) as Map),
            ),
          );
        } catch (_) {
          // Keep valid jobs available when one persisted entry is damaged.
        }
      }
      jobs.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      state = jobs;
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  SyncJob? findById(String id) =>
      state.where((job) => job.id == id).firstOrNull;

  SyncJob? findByName(String name) {
    final normalized = name.trim().toLowerCase();
    return state
        .where((job) => job.name.trim().toLowerCase() == normalized)
        .firstOrNull;
  }

  Future<SyncJob> create({
    required String name,
    required SyncEndpoint source,
    required SyncEndpoint destination,
    required SyncSelectionPolicy selectionPolicy,
    required Set<String> includedPaths,
    required Set<String> excludedPaths,
    SyncSchedule schedule = const SyncSchedule(),
    bool enabled = true,
  }) async {
    await loaded;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError.value(name, 'name');
    if (findByName(trimmedName) != null) {
      throw SyncJobNameConflict(trimmedName);
    }
    final now = DateTime.now();
    final job = SyncJob(
      id: const Uuid().v4(),
      name: trimmedName,
      source: source,
      destination: destination,
      selectionPolicy: selectionPolicy,
      includedPaths: Set.unmodifiable(includedPaths),
      excludedPaths: Set.unmodifiable(excludedPaths),
      schedule: schedule,
      enabled: enabled,
      createdAt: now,
      updatedAt: now,
    );
    state = [...state, job]
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    await _save();
    return job;
  }

  Future<void> update(SyncJob job) async {
    await loaded;
    final conflict = findByName(job.name);
    if (conflict != null && conflict.id != job.id) {
      throw SyncJobNameConflict(job.name);
    }
    final updated = job.copyWith(updatedAt: DateTime.now());
    state =
        state
            .map((current) => current.id == updated.id ? updated : current)
            .toList()
          ..sort(
            (left, right) =>
                left.name.toLowerCase().compareTo(right.name.toLowerCase()),
          );
    await _save();
  }

  Future<void> recordOutcome(
    String jobId,
    SyncRunOutcome outcome,
    DateTime completedAt,
  ) async {
    final job = findById(jobId);
    if (job == null) return;
    await update(job.copyWith(lastRunAt: completedAt, lastOutcome: outcome));
  }

  Future<void> delete(String id) async {
    await loaded;
    state = state.where((job) => job.id != id).toList();
    await _save();
  }

  Future<void> _save() async {
    final preferences = await AppPreferences.getInstance();
    await preferences.setStringList(
      _syncJobsKey,
      state.map((job) => jsonEncode(job.toJson())).toList(),
    );
  }
}

@Riverpod(keepAlive: true)
class SyncHistoryRepository extends _$SyncHistoryRepository {
  final Completer<void> _loaded = Completer<void>();

  @override
  List<SyncRunReport> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> get loaded => _loaded.future;

  Future<void> _load() async {
    try {
      final preferences = await AppPreferences.getInstance();
      final encodedReports =
          preferences.getStringList(_syncHistoryKey) ?? const [];
      final reports = <SyncRunReport>[];
      for (final encoded in encodedReports) {
        try {
          reports.add(
            SyncRunReport.fromJson(
              Map<String, dynamic>.from(jsonDecode(encoded) as Map),
            ),
          );
        } catch (_) {
          // A damaged history row must not hide later valid reports.
        }
      }
      reports.sort((left, right) => right.startedAt.compareTo(left.startedAt));
      state = reports.take(_maximumHistoryEntries).toList();
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  List<SyncRunReport> forJob(String jobId) =>
      state.where((report) => report.jobId == jobId).toList();

  Future<void> add(SyncRunReport report) async {
    await loaded;
    state = [report, ...state].take(_maximumHistoryEntries).toList();
    final preferences = await AppPreferences.getInstance();
    await preferences.setStringList(
      _syncHistoryKey,
      state.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    state = const [];
    final preferences = await AppPreferences.getInstance();
    await preferences.remove(_syncHistoryKey);
  }
}
