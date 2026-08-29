import 'dart:io';

import 'package:fir_file_manager/core/storage/providers/local_provider.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_service.dart';
import 'package:fir_file_manager/features/file_operations/sync_job_models.dart';
import 'package:fir_file_manager/features/file_operations/sync_job_runner.dart';
import 'package:fir_file_manager/features/file_operations/sync_models.dart';
import 'package:fir_file_manager/features/file_operations/sync_repositories.dart';
import 'package:fir_file_manager/features/file_operations/sync_scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SyncJob JSON preserves endpoints, policy, and weekly schedule', () {
    final now = DateTime(2026, 8, 10, 9, 30);
    final job = SyncJob(
      id: 'job-1',
      name: 'Documents backup',
      source: const SyncEndpoint(
        providerId: 'local',
        path: '/source',
        displayName: 'Local',
        volumeIdentity: 'source-volume',
      ),
      destination: const SyncEndpoint(
        providerId: 'smb-1',
        path: '/share/backup',
        displayName: 'NAS',
      ),
      selectionPolicy: const SyncSelectionPolicy(
        missing: true,
        modified: true,
        identical: false,
      ),
      includedPaths: const {'force.txt'},
      excludedPaths: const {'skip.tmp'},
      schedule: const SyncSchedule(
        type: SyncScheduleType.weekly,
        hour: 21,
        minute: 15,
        weekdays: {DateTime.monday, DateTime.friday},
        requireWifi: true,
      ),
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );

    final decoded = SyncJob.fromJson(job.toJson());

    expect(decoded.name, job.name);
    expect(decoded.source.volumeIdentity, 'source-volume');
    expect(decoded.selectionPolicy.identical, isFalse);
    expect(decoded.includedPaths, {'force.txt'});
    expect(decoded.excludedPaths, {'skip.tmp'});
    expect(decoded.schedule.type, SyncScheduleType.weekly);
    expect(decoded.schedule.weekdays, {DateTime.monday, DateTime.friday});
    expect(decoded.schedule.requireWifi, isTrue);
  });

  test('schedule calculates the next daily and weekly occurrence', () {
    final mondayMorning = DateTime(2026, 8, 10, 8);
    const daily = SyncSchedule(
      type: SyncScheduleType.daily,
      hour: 9,
      minute: 30,
    );
    const weekly = SyncSchedule(
      type: SyncScheduleType.weekly,
      hour: 7,
      weekdays: {DateTime.monday, DateTime.wednesday},
    );

    expect(daily.nextOccurrence(mondayMorning), DateTime(2026, 8, 10, 9, 30));
    expect(weekly.nextOccurrence(mondayMorning), DateTime(2026, 8, 12, 7));
  });

  test('Linux units preserve calendar, constraints, and escaped command', () {
    final now = DateTime(2026, 8, 10, 8);
    final job = SyncJob(
      id: r'job$1',
      name: 'Weekly\nbackup',
      source: const SyncEndpoint(
        providerId: 'local',
        path: '/source',
        displayName: 'Source',
      ),
      destination: const SyncEndpoint(
        providerId: 'local',
        path: '/backup',
        displayName: 'Backup',
      ),
      selectionPolicy: const SyncSelectionPolicy(),
      includedPaths: const {},
      excludedPaths: const {},
      schedule: const SyncSchedule(
        type: SyncScheduleType.weekly,
        hour: 9,
        minute: 5,
        weekdays: {DateTime.monday, DateTime.friday},
        missedRunPolicy: SyncMissedRunPolicy.runWhenAvailable,
        requireWifi: true,
        requireCharging: true,
      ),
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );

    expect(
      buildLinuxCalendar(job.schedule),
      'OnCalendar=Mon,Fri *-*-* 09:05:00',
    );
    final service = buildLinuxServiceUnit(
      job,
      executable: r'/opt/Fir 100%/$fir',
    );
    expect(service, contains('Description=Fir SmartSync - Weekly backup'));
    expect(service, contains('Wants=network-online.target'));
    expect(service, contains('ConditionACPower=true'));
    expect(service, contains(r'ExecStart="/opt/Fir 100%%/$$fir"'));
    expect(service, contains(r'--run-sync-id "job$$1"'));
    final timer = buildLinuxTimerUnit(
      job,
      serviceName: 'fir-smartsync.service',
    );
    expect(timer, contains('Persistent=true'));
    expect(timer, contains('Unit=fir-smartsync.service'));
  });

  test(
    'Windows task XML preserves schedule, conditions, and command paths',
    () {
      final now = DateTime(2026, 8, 10, 8);
      final job = SyncJob(
        id: 'job&1',
        name: 'Weekly backup',
        source: const SyncEndpoint(
          providerId: 'local',
          path: r'C:\Source',
          displayName: 'Source',
        ),
        destination: const SyncEndpoint(
          providerId: 'local',
          path: r'D:\Backup',
          displayName: 'Backup',
        ),
        selectionPolicy: const SyncSelectionPolicy(),
        includedPaths: const {},
        excludedPaths: const {},
        schedule: const SyncSchedule(
          type: SyncScheduleType.weekly,
          hour: 9,
          weekdays: {DateTime.monday, DateTime.friday},
          missedRunPolicy: SyncMissedRunPolicy.runWhenAvailable,
          requireWifi: true,
          requireCharging: true,
        ),
        enabled: true,
        createdAt: now,
        updatedAt: now,
      );

      final xml = buildWindowsTaskXml(
        job,
        executable: r'C:\Fir & Co\fir_file_manager.exe',
        after: now,
      );

      expect(
        xml,
        contains('<StartBoundary>2026-08-10T09:00:00</StartBoundary>'),
      );
      expect(xml, contains('<Monday/><Friday/>'));
      expect(xml, contains('<StartWhenAvailable>true</StartWhenAvailable>'));
      expect(xml, contains('<RunOnlyIfNetworkAvailable>true'));
      expect(xml, contains('<DisallowStartIfOnBatteries>true'));
      expect(xml, contains(r'C:\Fir &amp; Co\fir_file_manager.exe'));
      expect(xml, contains('job&amp;1'));
    },
  );

  test('saved job runs by name and records its observable result', () async {
    SharedPreferences.setMockInitialValues({});
    final temporary = await Directory.systemTemp.createTemp('fir-sync-job-');
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, null),
    );
    addTearDown(() => temporary.delete(recursive: true));
    final source = Directory('${temporary.path}/source')..createSync();
    final destination = Directory('${temporary.path}/destination')
      ..createSync();
    final sourceFile = File('${source.path}/report.txt')
      ..writeAsStringSync('Fir SmartSync');
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final repository = container.read(syncJobRepositoryProvider.notifier);
    await repository.loaded;
    final job = await repository.create(
      name: 'Local backup',
      source: SyncEndpoint(
        providerId: 'local',
        path: source.path,
        displayName: 'Local',
      ),
      destination: SyncEndpoint(
        providerId: 'local',
        path: destination.path,
        displayName: 'Local',
      ),
      selectionPolicy: const SyncSelectionPolicy(),
      includedPaths: const {},
      excludedPaths: const {},
    );

    final report = await container
        .read(syncJobRunnerProvider.notifier)
        .runByName('Local backup');

    expect(report.jobId, job.id);
    expect(report.outcome, SyncRunOutcome.success);
    expect(report.createdFiles, 1);
    expect(report.failedFiles, 0);
    expect(report.transferredBytes, sourceFile.lengthSync());
    expect(
      File('${destination.path}/report.txt').readAsStringSync(),
      'Fir SmartSync',
    );
    final brokenJob = await repository.create(
      name: 'Unavailable backup',
      source: const SyncEndpoint(
        providerId: 'missing-connection',
        path: '/remote',
        displayName: 'Missing',
      ),
      destination: SyncEndpoint(
        providerId: 'local',
        path: destination.path,
        displayName: 'Local',
      ),
      selectionPolicy: const SyncSelectionPolicy(),
      includedPaths: const {},
      excludedPaths: const {},
    );
    final failedReport = await container
        .read(syncJobRunnerProvider.notifier)
        .run(brokenJob);
    expect(failedReport.outcome, SyncRunOutcome.failed);
    expect(failedReport.failures.single.relativePath, '<preflight>');
    expect(failedReport.failures.single.message, contains('was not found'));
    expect(container.read(syncHistoryRepositoryProvider), hasLength(2));
    final history = container.read(syncHistoryRepositoryProvider);
    expect(history.map((report) => report.jobName), [
      'Unavailable backup',
      'Local backup',
    ]);
  });
  test(
    'sync analysis skips symlinked directories without duplicate traversal',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'fir-sync-symlink-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final source = Directory('${temporary.path}/source')..createSync();
      final destination = Directory('${temporary.path}/destination')
        ..createSync();
      File('${source.path}/report.txt').writeAsStringSync('Fir SmartSync');
      Link('${source.path}/loop').createSync(source.path);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final items = await container
          .read(fileOperationsServiceProvider.notifier)
          .analyzeSync(
            sourceProvider: LocalProvider(),
            sourcePath: source.path,
            destProvider: LocalProvider(),
            destPath: destination.path,
          );

      expect(
        items.where((item) => item.relativePath == 'report.txt'),
        hasLength(1),
      );
      expect(items.any((item) => item.relativePath.contains('loop')), isFalse);
    },
  );
}
