import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/storage_provider.dart';
import '../../core/storage/storage_provider_service.dart';
import '../connections/connection_repository.dart';
import 'file_operations_service.dart';
import 'sync_job_models.dart';
import 'sync_models.dart';
import 'sync_repositories.dart';

part 'sync_job_runner.g.dart';

class SyncJobAlreadyRunning implements Exception {
  const SyncJobAlreadyRunning(this.jobId);

  final String jobId;

  @override
  String toString() => 'Synchronization job $jobId is already running.';
}

class SyncDestinationBusy implements Exception {
  const SyncDestinationBusy(this.destination);

  final String destination;

  @override
  String toString() =>
      'Destination $destination is already being synchronized.';
}

@Riverpod(keepAlive: true)
class SyncJobRunner extends _$SyncJobRunner {
  final Set<String> _destinationLocks = {};
  @override
  Set<String> build() => const {};

  Future<SyncRunReport> runByName(
    String name, {
    SyncRunTrigger trigger = SyncRunTrigger.manual,
  }) async {
    final repository = ref.read(syncJobRepositoryProvider.notifier);
    await repository.loaded;
    final job = repository.findByName(name);
    if (job == null) {
      throw StateError('Synchronization job "$name" was not found.');
    }
    return run(job, trigger: trigger);
  }

  Future<SyncRunReport> runById(
    String id, {
    SyncRunTrigger trigger = SyncRunTrigger.manual,
  }) async {
    final repository = ref.read(syncJobRepositoryProvider.notifier);
    await repository.loaded;
    final job = repository.findById(id);
    if (job == null) {
      throw StateError('Synchronization job "$id" was not found.');
    }
    return run(job, trigger: trigger);
  }

  Future<SyncRunReport> run(
    SyncJob job, {
    SyncRunTrigger trigger = SyncRunTrigger.manual,
  }) async {
    if (state.contains(job.id)) throw SyncJobAlreadyRunning(job.id);
    state = {...state, job.id};
    final startedAt = DateTime.now();
    var scannedFiles = 0;
    var selectedFiles = 0;
    final destinationLock =
        '${job.destination.providerId}:${job.destination.path}';
    var destinationLockAcquired = false;

    try {
      if (_destinationLocks.contains(destinationLock)) {
        throw SyncDestinationBusy(job.destination.path);
      }
      _destinationLocks.add(destinationLock);
      destinationLockAcquired = true;
      if (job.source.providerId == job.destination.providerId &&
          job.source.path == job.destination.path) {
        throw StateError('Source and destination are the same directory.');
      }
      await _validateVolumeIdentity(job.source);
      await _validateVolumeIdentity(job.destination);

      final sourceProvider = await _resolveProvider(job.source.providerId);
      final destinationProvider = await _resolveProvider(
        job.destination.providerId,
      );
      final service = ref.read(fileOperationsServiceProvider.notifier);
      final items = await service.analyzeSync(
        sourceProvider: sourceProvider,
        sourcePath: job.source.path,
        destProvider: destinationProvider,
        destPath: job.destination.path,
      );
      scannedFiles = items.length;

      final selected = <SyncItem>[];
      for (final item in items) {
        var shouldSelect = job.selectionPolicy.selects(item.status);
        if (job.includedPaths.contains(item.relativePath)) shouldSelect = true;
        if (job.excludedPaths.contains(item.relativePath)) shouldSelect = false;
        if (!item.canSelect) shouldSelect = false;
        item.isSelected = shouldSelect;
        if (shouldSelect) selected.add(item);
      }
      selectedFiles = selected.length;

      final result = selected.isEmpty
          ? const SyncExecutionResult(
              createdFiles: 0,
              updatedFiles: 0,
              failedFiles: 0,
              cancelled: false,
            )
          : await service.executeSync(
              sourceProvider: sourceProvider,
              destProvider: destinationProvider,
              destPath: job.destination.path,
              selectedItems: selected,
            );
      final completedAt = DateTime.now();
      final outcome = result.cancelled
          ? SyncRunOutcome.cancelled
          : result.failedFiles > 0 && result.successfulFiles > 0
          ? SyncRunOutcome.partialFailure
          : result.failedFiles > 0
          ? SyncRunOutcome.failed
          : SyncRunOutcome.success;
      final report = SyncRunReport(
        id: const Uuid().v4(),
        jobId: job.id,
        jobName: job.name,
        trigger: trigger,
        startedAt: startedAt,
        completedAt: completedAt,
        outcome: outcome,
        scannedFiles: scannedFiles,
        selectedFiles: selectedFiles,
        createdFiles: result.createdFiles,
        updatedFiles: result.updatedFiles,
        failedFiles: result.failedFiles,
        transferredBytes: result.transferredBytes,
        failures: result.failures,
      );
      await _record(job.id, report);
      return report;
    } catch (error) {
      final completedAt = DateTime.now();
      final report = SyncRunReport(
        id: const Uuid().v4(),
        jobId: job.id,
        jobName: job.name,
        trigger: trigger,
        startedAt: startedAt,
        completedAt: completedAt,
        outcome: SyncRunOutcome.failed,
        scannedFiles: scannedFiles,
        selectedFiles: selectedFiles,
        createdFiles: 0,
        updatedFiles: 0,
        failedFiles: 1,
        transferredBytes: 0,
        failures: [
          SyncFileFailure(
            relativePath: '<preflight>',
            message: error.toString().split('\n').first,
          ),
        ],
      );
      await _record(job.id, report);
      return report;
    } finally {
      state = {...state}..remove(job.id);
      if (destinationLockAcquired) {
        _destinationLocks.remove(destinationLock);
      }
    }
  }

  Future<void> _validateVolumeIdentity(SyncEndpoint endpoint) async {
    final expected = endpoint.volumeIdentity;
    if (!Platform.isAndroid ||
        endpoint.providerId != 'local' ||
        expected == null) {
      return;
    }
    final actual = await const MethodChannel(
      'fir_file_manager/file_actions',
    ).invokeMethod<String>('storageIdentity', {'path': endpoint.path});
    if (actual != expected) {
      throw StateError(
        'The storage volume for ${endpoint.path} is not the saved volume.',
      );
    }
  }

  Future<void> _record(String jobId, SyncRunReport report) async {
    await ref.read(syncHistoryRepositoryProvider.notifier).add(report);
    await ref
        .read(syncJobRepositoryProvider.notifier)
        .recordOutcome(jobId, report.outcome, report.completedAt);
  }

  Future<StorageProvider> _resolveProvider(String providerId) async {
    final registry = ref.read(storageProviderRegistryProvider.notifier);
    if (providerId == 'local') return registry.local;

    final connections = ref.read(connectionRepositoryProvider.notifier);
    await connections.loaded;
    final profile = connections.getById(providerId);
    if (profile == null) {
      throw StateError('Saved connection "$providerId" was not found.');
    }
    return registry.getOrCreate(
      profile,
      password: await connections.getPassword(profile.id),
      privateKey: await connections.getPrivateKey(profile.id),
      clientId: await connections.getClientId(profile.id),
      clientSecret: await connections.getClientSecret(profile.id),
    );
  }
}
