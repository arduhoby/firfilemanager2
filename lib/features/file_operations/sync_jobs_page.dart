import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../shell_adaptive/sync_job_dialog.dart';
import 'sync_job_models.dart';
import 'sync_job_runner.dart';
import 'sync_repositories.dart';
import 'sync_scheduler.dart';

class SyncJobsPage extends ConsumerWidget {
  const SyncJobsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = gen.AppLocalizations.of(context)!;
    final jobs = ref.watch(syncJobRepositoryProvider);
    final running = ref.watch(syncJobRunnerProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.sync_lock),
            const SizedBox(width: 10),
            Text(l10n.syncJobsTitle),
          ],
        ),
      ),
      body: jobs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_send_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.syncJobsEmpty, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      l10n.syncJobsEmptyHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final job = jobs[index];
                return _SyncJobCard(
                  job: job,
                  running: running.contains(job.id),
                  onRun: () => _run(context, ref, job),
                  onEdit: () => _edit(context, ref, job),
                  onToggle: (enabled) => _toggle(context, ref, job, enabled),
                  onHistory: () => _showHistory(context, ref, job),
                  onDelete: () => _delete(context, ref, job),
                );
              },
            ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, SyncJob job) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final report = await ref.read(syncJobRunnerProvider.notifier).run(job);
    if (!context.mounted) return;
    final message = report.outcome == SyncRunOutcome.success
        ? l10n.syncRunSucceeded(report.updatedFiles, report.createdFiles)
        : l10n.syncRunFailed(report.failedFiles);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: report.outcome == SyncRunOutcome.success
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, SyncJob job) async {
    final result = await showDialog<SyncJobEditorResult>(
      context: context,
      builder: (context) => SyncJobDialog(job: job),
    );
    if (result == null) return;
    try {
      final updated = job.copyWith(
        name: result.name,
        schedule: result.schedule,
        enabled: result.enabled,
      );
      await _replaceScheduledJob(ref, original: job, updated: updated);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    SyncJob job,
    bool enabled,
  ) async {
    try {
      final updated = job.copyWith(enabled: enabled);
      await _replaceScheduledJob(ref, original: job, updated: updated);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _replaceScheduledJob(
    WidgetRef ref, {
    required SyncJob original,
    required SyncJob updated,
  }) async {
    final repository = ref.read(syncJobRepositoryProvider.notifier);
    final scheduler = ref.read(syncSchedulerProvider.notifier);
    await repository.update(updated);
    try {
      await scheduler.apply(updated);
    } catch (_) {
      await repository.update(original);
      try {
        await scheduler.apply(original);
      } catch (_) {
        // The original error is the actionable scheduling failure.
      }
      rethrow;
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SyncJob job) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncDeleteJob),
        content: Text(l10n.syncDeleteJobConfirm(job.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncSchedulerProvider.notifier).remove(job.id);
    await ref.read(syncJobRepositoryProvider.notifier).delete(job.id);
  }

  Future<void> _showHistory(
    BuildContext context,
    WidgetRef ref,
    SyncJob job,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final repository = ref.read(syncHistoryRepositoryProvider.notifier);
    await repository.loaded;
    final reports = repository.forJob(job.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncHistoryFor(job.name)),
        content: SizedBox(
          width: 620,
          height: 420,
          child: reports.isEmpty
              ? Center(child: Text(l10n.syncHistoryEmpty))
              : ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final report = reports[index];
                    return ListTile(
                      leading: Icon(
                        report.outcome == SyncRunOutcome.success
                            ? Icons.check_circle
                            : Icons.error,
                        color: report.outcome == SyncRunOutcome.success
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        DateFormat.yMd(
                          Localizations.localeOf(context).toLanguageTag(),
                        ).add_Hm().format(report.startedAt),
                      ),
                      subtitle: Text(
                        '${report.updatedFiles} ${l10n.syncStatusDifferent.toLowerCase()} · '
                        '${report.createdFiles} ${l10n.syncStatusNew.toLowerCase()} · '
                        '${report.failedFiles} ${l10n.syncFailedLabel.toLowerCase()} · '
                        '${filesize(report.transferredBytes)}',
                      ),
                      trailing: Text('${report.duration.inSeconds}s'),
                      onTap: report.failures.isEmpty
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(l10n.syncFailureDetails),
                                content: SizedBox(
                                  width: 560,
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: report.failures
                                        .map(
                                          (failure) => ListTile(
                                            title: Text(failure.relativePath),
                                            subtitle: Text(failure.message),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }
}

class _SyncJobCard extends StatelessWidget {
  const _SyncJobCard({
    required this.job,
    required this.running,
    required this.onRun,
    required this.onEdit,
    required this.onToggle,
    required this.onHistory,
    required this.onDelete,
  });

  final SyncJob job;
  final bool running;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: running
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.name, style: theme.textTheme.titleMedium),
                      Text(
                        '${job.source.displayName}: ${job.source.path}\n'
                        '→ ${job.destination.displayName}: ${job.destination.path}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(value: job.enabled, onChanged: onToggle),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.schedule, size: 17),
                  label: Text(_scheduleLabel(l10n, job)),
                ),
                if (job.lastRunAt != null)
                  Chip(
                    avatar: Icon(
                      job.lastOutcome == SyncRunOutcome.success
                          ? Icons.check
                          : Icons.error_outline,
                      size: 17,
                    ),
                    label: Text(
                      DateFormat.yMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).add_Hm().format(job.lastRunAt!),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: running ? null : onRun,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.syncRunNow),
                ),
                OutlinedButton.icon(
                  onPressed: onHistory,
                  icon: const Icon(Icons.history),
                  label: Text(l10n.syncHistory),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: l10n.actionEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: l10n.actionDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scheduleLabel(gen.AppLocalizations l10n, SyncJob job) {
    final schedule = job.schedule;
    return switch (schedule.type) {
      SyncScheduleType.manual => l10n.syncScheduleManual,
      SyncScheduleType.once => l10n.syncScheduleOnce,
      SyncScheduleType.daily =>
        '${l10n.syncScheduleDaily} ${_two(schedule.hour)}:${_two(schedule.minute)}',
      SyncScheduleType.weekly =>
        '${l10n.syncScheduleWeekly} ${_two(schedule.hour)}:${_two(schedule.minute)}',
    };
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
