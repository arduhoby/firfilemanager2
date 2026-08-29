import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../file_operations/sync_job_models.dart';

class SyncJobEditorResult {
  const SyncJobEditorResult({
    required this.name,
    required this.schedule,
    required this.enabled,
  });

  final String name;
  final SyncSchedule schedule;
  final bool enabled;
}

class SyncJobDialog extends StatefulWidget {
  const SyncJobDialog({super.key, this.job, this.suggestedName});

  final SyncJob? job;
  final String? suggestedName;

  @override
  State<SyncJobDialog> createState() => _SyncJobDialogState();
}

class _SyncJobDialogState extends State<SyncJobDialog> {
  late final TextEditingController _nameController;
  late SyncScheduleType _type;
  late TimeOfDay _time;
  late Set<int> _weekdays;
  late DateTime _onceAt;
  late bool _enabled;
  late bool _requireWifi;
  late bool _allowMobileData;
  late bool _requireCharging;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final schedule = widget.job?.schedule ?? const SyncSchedule();
    _nameController = TextEditingController(
      text: widget.job?.name ?? widget.suggestedName ?? '',
    );
    _type = schedule.type;
    _time = TimeOfDay(hour: schedule.hour, minute: schedule.minute);
    _weekdays = {...schedule.weekdays};
    _onceAt = schedule.onceAt ?? DateTime.now().add(const Duration(hours: 1));
    _enabled = widget.job?.enabled ?? true;
    _requireWifi = schedule.requireWifi;
    _allowMobileData = schedule.allowMobileData;
    _requireCharging = schedule.requireCharging;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null) setState(() => _time = value);
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _onceAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null) {
      setState(() {
        _onceAt = DateTime(
          value.year,
          value.month,
          value.day,
          _time.hour,
          _time.minute,
        );
      });
    }
  }

  void _submit() {
    final l10n = gen.AppLocalizations.of(context)!;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = l10n.syncJobNameRequired);
      return;
    }
    if (_type == SyncScheduleType.weekly && _weekdays.isEmpty) {
      setState(() => _nameError = l10n.syncWeekdayRequired);
      return;
    }
    final onceAt = _type == SyncScheduleType.once
        ? DateTime(
            _onceAt.year,
            _onceAt.month,
            _onceAt.day,
            _time.hour,
            _time.minute,
          )
        : null;
    Navigator.pop(
      context,
      SyncJobEditorResult(
        name: name,
        enabled: _enabled,
        schedule: SyncSchedule(
          type: _type,
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _weekdays,
          onceAt: onceAt,
          requireWifi: _requireWifi,
          allowMobileData: _allowMobileData,
          requireCharging: _requireCharging,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final locale = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.job == null ? l10n.syncSaveJob : l10n.syncEditJob),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.syncJobName,
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SyncScheduleType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: l10n.syncSchedule,
                  prefixIcon: const Icon(Icons.schedule),
                ),
                items: [
                  DropdownMenuItem(
                    value: SyncScheduleType.manual,
                    child: Text(l10n.syncScheduleManual),
                  ),
                  DropdownMenuItem(
                    value: SyncScheduleType.once,
                    child: Text(l10n.syncScheduleOnce),
                  ),
                  DropdownMenuItem(
                    value: SyncScheduleType.daily,
                    child: Text(l10n.syncScheduleDaily),
                  ),
                  DropdownMenuItem(
                    value: SyncScheduleType.weekly,
                    child: Text(l10n.syncScheduleWeekly),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _type = value ?? SyncScheduleType.manual),
              ),
              if (_type != SyncScheduleType.manual) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time),
                  label: Text(locale.formatTimeOfDay(_time)),
                ),
              ],
              if (_type == SyncScheduleType.once) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event),
                  label: Text(locale.formatFullDate(_onceAt)),
                ),
              ],
              if (_type == SyncScheduleType.weekly) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(7, (index) {
                    final weekday = index + 1;
                    return FilterChip(
                      selected: _weekdays.contains(weekday),
                      label: Text(_weekdayLabel(l10n, weekday)),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _weekdays.add(weekday);
                        } else {
                          _weekdays.remove(weekday);
                        }
                      }),
                    );
                  }),
                ),
              ],
              if (_type != SyncScheduleType.manual) ...[
                const Divider(height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  title: Text(l10n.syncJobEnabled),
                  onChanged: (value) => setState(() => _enabled = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _requireWifi,
                  title: Text(l10n.syncRequireWifi),
                  onChanged: (value) =>
                      setState(() => _requireWifi = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowMobileData,
                  title: Text(l10n.syncAllowMobileData),
                  onChanged: (value) =>
                      setState(() => _allowMobileData = value ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _requireCharging,
                  title: Text(l10n.syncRequireCharging),
                  onChanged: (value) =>
                      setState(() => _requireCharging = value ?? false),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(l10n.actionSave),
        ),
      ],
    );
  }

  String _weekdayLabel(gen.AppLocalizations l10n, int weekday) =>
      switch (weekday) {
        DateTime.monday => l10n.weekdayMonday,
        DateTime.tuesday => l10n.weekdayTuesday,
        DateTime.wednesday => l10n.weekdayWednesday,
        DateTime.thursday => l10n.weekdayThursday,
        DateTime.friday => l10n.weekdayFriday,
        DateTime.saturday => l10n.weekdaySaturday,
        DateTime.sunday => l10n.weekdaySunday,
        _ => '',
      };
}
