import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'sync_job_models.dart';

part 'sync_scheduler.g.dart';

class SyncScheduleException implements Exception {
  const SyncScheduleException(this.message);

  final String message;

  @override
  String toString() => message;
}

@Riverpod(keepAlive: true)
class SyncScheduler extends _$SyncScheduler {
  static const _androidChannel = MethodChannel(
    'fir_file_manager/sync_scheduler',
  );

  @override
  void build() {}

  Future<void> apply(SyncJob job) async {
    await remove(job.id);
    if (!job.enabled || !job.schedule.isScheduled) return;

    if (Platform.isLinux) {
      await _scheduleLinux(job);
    } else if (Platform.isWindows) {
      await _scheduleWindows(job);
    } else if (Platform.isAndroid) {
      await _scheduleAndroid(job);
    } else {
      throw const SyncScheduleException(
        'Scheduled synchronization is not supported on this platform.',
      );
    }
  }

  Future<void> remove(String jobId) async {
    if (Platform.isLinux) {
      await _removeLinux(jobId);
    } else if (Platform.isWindows) {
      await Process.run('schtasks.exe', [
        '/Delete',
        '/F',
        '/TN',
        _windowsTaskName(jobId),
      ]);
    } else if (Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('cancel', {'jobId': jobId});
    }
  }

  Future<void> _scheduleLinux(SyncJob job) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const SyncScheduleException(
        'HOME is unavailable for systemd timer setup.',
      );
    }
    final userDirectory = Directory(p.join(home, '.config', 'systemd', 'user'));
    await userDirectory.create(recursive: true);
    final serviceName = _linuxServiceName(job.id);
    final timerName = _linuxTimerName(job.id);
    final service = File(p.join(userDirectory.path, serviceName));
    final timer = File(p.join(userDirectory.path, timerName));

    await service.writeAsString(
      buildLinuxServiceUnit(job, executable: Platform.resolvedExecutable),
      flush: true,
    );
    await timer.writeAsString(
      buildLinuxTimerUnit(job, serviceName: serviceName),
      flush: true,
    );

    await _runChecked('systemctl', ['--user', 'daemon-reload']);
    await _runChecked('systemctl', ['--user', 'enable', '--now', timerName]);
  }

  Future<void> _removeLinux(String jobId) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    final directory = Directory(p.join(home, '.config', 'systemd', 'user'));
    final timerName = _linuxTimerName(jobId);
    await Process.run('systemctl', ['--user', 'disable', '--now', timerName]);
    final timer = File(p.join(directory.path, timerName));
    final service = File(p.join(directory.path, _linuxServiceName(jobId)));
    if (await timer.exists()) await timer.delete();
    if (await service.exists()) await service.delete();
    await Process.run('systemctl', ['--user', 'daemon-reload']);
  }

  Future<void> _scheduleWindows(SyncJob job) async {
    final taskXml = buildWindowsTaskXml(
      job,
      executable: Platform.resolvedExecutable,
      after: DateTime.now(),
    );
    final temporary = File(
      p.join(Directory.systemTemp.path, 'fir-smartsync-${job.id}.xml'),
    );
    try {
      await temporary.writeAsString(taskXml, flush: true);
      await _runChecked('schtasks.exe', [
        '/Create',
        '/F',
        '/TN',
        _windowsTaskName(job.id),
        '/XML',
        temporary.path,
      ]);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _scheduleAndroid(SyncJob job) async {
    final nextRun = job.schedule.nextOccurrence(DateTime.now());
    if (nextRun == null) {
      throw const SyncScheduleException(
        'The Android schedule has no future run time.',
      );
    }
    await _androidChannel.invokeMethod<void>('schedule', {
      'jobId': job.id,
      'jobName': job.name,
      'scheduleType': job.schedule.type.name,
      'hour': job.schedule.hour,
      'minute': job.schedule.minute,
      'weekdays': job.schedule.weekdays.toList(),
      'onceAtMillis': job.schedule.onceAt?.millisecondsSinceEpoch,
      'nextRunAtMillis': nextRun.millisecondsSinceEpoch,
      'runWhenAvailable':
          job.schedule.missedRunPolicy == SyncMissedRunPolicy.runWhenAvailable,
      'requireWifi': job.schedule.requireWifi,
      'allowMobileData': job.schedule.allowMobileData,
      'requireCharging': job.schedule.requireCharging,
    });
  }

  Future<void> _runChecked(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      final message = result.stderr.toString().trim();
      throw SyncScheduleException(
        message.isEmpty
            ? '$executable failed with exit code ${result.exitCode}.'
            : message,
      );
    }
  }

  String _linuxServiceName(String id) => 'fir-smartsync-$id.service';
  String _linuxTimerName(String id) => 'fir-smartsync-$id.timer';
  String _windowsTaskName(String id) => 'FirFileManager-SmartSync-$id';
}

String buildLinuxServiceUnit(SyncJob job, {required String executable}) {
  final conditions = [
    if (job.schedule.requireWifi) 'Wants=network-online.target',
    if (job.schedule.requireWifi) 'After=network-online.target',
    if (job.schedule.requireCharging) 'ConditionACPower=true',
  ].join('\n');
  return '[Unit]\n'
      'Description=Fir SmartSync - ${_systemdDescription(job.name)}\n'
      '$conditions\n\n'
      '[Service]\n'
      'Type=oneshot\n'
      'ExecStart=${_systemdQuote(executable)} --run-sync-id '
      '${_systemdQuote(job.id)}\n';
}

String buildLinuxTimerUnit(SyncJob job, {required String serviceName}) =>
    '[Unit]\n'
    'Description=Fir SmartSync schedule - ${_systemdDescription(job.name)}\n\n'
    '[Timer]\n'
    '${buildLinuxCalendar(job.schedule)}\n'
    'Persistent=${job.schedule.missedRunPolicy == SyncMissedRunPolicy.runWhenAvailable ? 'true' : 'false'}\n'
    'Unit=$serviceName\n\n'
    '[Install]\n'
    'WantedBy=timers.target\n';

String buildLinuxCalendar(SyncSchedule schedule) {
  final time = '${_two(schedule.hour)}:${_two(schedule.minute)}:00';
  switch (schedule.type) {
    case SyncScheduleType.manual:
      throw const SyncScheduleException('A manual job has no calendar.');
    case SyncScheduleType.once:
      final onceAt = schedule.onceAt;
      if (onceAt == null) {
        throw const SyncScheduleException(
          'A one-time schedule requires a date.',
        );
      }
      return 'OnCalendar=${onceAt.year}-${_two(onceAt.month)}-'
          '${_two(onceAt.day)} ${_two(onceAt.hour)}:'
          '${_two(onceAt.minute)}:00';
    case SyncScheduleType.daily:
      return 'OnCalendar=*-*-* $time';
    case SyncScheduleType.weekly:
      if (schedule.weekdays.isEmpty) {
        throw const SyncScheduleException(
          'A weekly schedule requires a weekday.',
        );
      }
      final days = schedule.weekdays.map(_systemdWeekday).join(',');
      return 'OnCalendar=$days *-*-* $time';
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

String _systemdQuote(String value) =>
    '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('%', '%%').replaceAll(r'$', r'$$')}"';

String _systemdDescription(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

String _systemdWeekday(int weekday) => const {
  DateTime.monday: 'Mon',
  DateTime.tuesday: 'Tue',
  DateTime.wednesday: 'Wed',
  DateTime.thursday: 'Thu',
  DateTime.friday: 'Fri',
  DateTime.saturday: 'Sat',
  DateTime.sunday: 'Sun',
}[weekday]!;

String buildWindowsTaskXml(
  SyncJob job, {
  required String executable,
  required DateTime after,
}) {
  final schedule = job.schedule;
  if (!schedule.isScheduled) {
    throw const SyncScheduleException('A manual job has no schedule.');
  }
  final start = schedule.nextOccurrence(after);
  if (start == null) {
    throw const SyncScheduleException('The schedule has no future run time.');
  }
  final boundary =
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}T'
      '${start.hour.toString().padLeft(2, '0')}:'
      '${start.minute.toString().padLeft(2, '0')}:00';
  final calendar = switch (schedule.type) {
    SyncScheduleType.manual => throw const SyncScheduleException(
      'A manual job has no schedule.',
    ),
    SyncScheduleType.once => '',
    SyncScheduleType.daily =>
      '<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>',
    SyncScheduleType.weekly =>
      '<ScheduleByWeek><WeeksInterval>1</WeeksInterval><DaysOfWeek>'
          '${schedule.weekdays.map(_windowsXmlWeekday).join()}'
          '</DaysOfWeek></ScheduleByWeek>',
  };
  final trigger = schedule.type == SyncScheduleType.once
      ? '<TimeTrigger><StartBoundary>$boundary</StartBoundary>'
            '<Enabled>true</Enabled></TimeTrigger>'
      : '<CalendarTrigger><StartBoundary>$boundary</StartBoundary>'
            '<Enabled>true</Enabled>$calendar</CalendarTrigger>';
  final startWhenAvailable =
      schedule.missedRunPolicy == SyncMissedRunPolicy.runWhenAvailable;
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<Task version="1.4" '
      'xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">'
      '<Triggers>$trigger</Triggers>'
      '<Principals><Principal id="Author">'
      '<LogonType>InteractiveToken</LogonType>'
      '<RunLevel>LeastPrivilege</RunLevel>'
      '</Principal></Principals>'
      '<Settings>'
      '<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>'
      '<DisallowStartIfOnBatteries>${schedule.requireCharging}</DisallowStartIfOnBatteries>'
      '<StopIfGoingOnBatteries>${schedule.requireCharging}</StopIfGoingOnBatteries>'
      '<RunOnlyIfNetworkAvailable>${schedule.requireWifi}</RunOnlyIfNetworkAvailable>'
      '<StartWhenAvailable>$startWhenAvailable</StartWhenAvailable>'
      '<AllowHardTerminate>true</AllowHardTerminate>'
      '<ExecutionTimeLimit>PT0S</ExecutionTimeLimit>'
      '<Enabled>true</Enabled>'
      '</Settings>'
      '<Actions Context="Author"><Exec>'
      '<Command>${_xmlEscape(executable)}</Command>'
      '<Arguments>--run-sync-id ${_xmlEscape(job.id)}</Arguments>'
      '</Exec></Actions>'
      '</Task>';
}

String _windowsXmlWeekday(int weekday) =>
    '<${const {DateTime.monday: 'Monday', DateTime.tuesday: 'Tuesday', DateTime.wednesday: 'Wednesday', DateTime.thursday: 'Thursday', DateTime.friday: 'Friday', DateTime.saturday: 'Saturday', DateTime.sunday: 'Sunday'}[weekday]!}/>';

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
