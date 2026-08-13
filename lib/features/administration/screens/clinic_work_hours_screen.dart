import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/clinic_work_hours.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/clinic_operating_status_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class ClinicWorkHoursScreen extends ConsumerStatefulWidget {
  const ClinicWorkHoursScreen({super.key});

  @override
  ConsumerState<ClinicWorkHoursScreen> createState() =>
      _ClinicWorkHoursScreenState();
}

class _ClinicWorkHoursScreenState extends ConsumerState<ClinicWorkHoursScreen> {
  String _timeZone = 'Africa/Lagos';
  bool _enabled = true;
  List<ClinicWorkDayConfig> _days = const [];
  String? _loadedClinicId;
  bool _saving = false;

  void _hydrate(ClinicWorkHoursConfig config) {
    if (_loadedClinicId == config.clinicId) return;
    _loadedClinicId = config.clinicId;
    _timeZone = config.timeZone;
    _enabled = config.isEnabled;
    _days = List.of(config.days);
  }

  bool _canManage(UserSession session) =>
      session.can(Permissions.clinicWorkHoursManage) ||
      session.can(Permissions.clinicSettingsEdit);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider);
    final workHours = ref.watch(clinicWorkHoursProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Work Hours')),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _WorkHoursMessage(
          title: 'Work hours unavailable',
          message: 'Sign in again to review this clinic setting.',
          onRetry: () {
            ref.invalidate(userSessionProvider);
            ref.invalidate(clinicWorkHoursProvider);
          },
        ),
        data: (userSession) => workHours.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _WorkHoursMessage(
            title: 'Work hours unavailable',
            message: 'Try again shortly. Your clinic data is safe.',
            onRetry: () => ref.invalidate(clinicWorkHoursProvider),
          ),
          data: (config) {
            if (config == null) {
              return const _WorkHoursMessage(
                title: 'Work hours unavailable',
                message: 'Finish clinic setup before configuring work hours.',
              );
            }
            _hydrate(config);
            final canManage = _canManage(userSession);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                AveraPageHeader(
                  title: 'Clinic schedule',
                  subtitle: canManage
                      ? 'Set opening hours, breaks, and the clinic time zone.'
                      : 'Contact your clinic administrator to update work hours.',
                ),
                const SizedBox(height: AveraSpacing.sectionGap),
                AveraLabeledSwitchField(
                  label: 'Availability',
                  title: 'Work hours enabled',
                  subtitle: 'Show operating status to clinic staff',
                  value: _enabled,
                  onChanged: canManage
                      ? (value) => setState(() => _enabled = value)
                      : null,
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                AveraLabeledDropdownField<String>(
                  label: 'Time zone',
                  hintText: 'Select time zone',
                  value: _timeZone,
                  items: const [
                    DropdownMenuItem(
                      value: 'Africa/Lagos',
                      child: Text('Africa/Lagos'),
                    ),
                    DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                  ],
                  onChanged: canManage
                      ? (value) =>
                            setState(() => _timeZone = value ?? _timeZone)
                      : null,
                ),
                const SizedBox(height: AveraSpacing.sectionGap),
                const AveraSectionHeader(
                  title: 'Working days',
                  subtitle: 'Choose opening, closing, and break times.',
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                for (var index = 0; index < _days.length; index++)
                  _WorkDayEditor(
                    day: _days[index],
                    enabled: canManage && _enabled,
                    onChanged: (day) => setState(() => _days[index] = day),
                  ),
                if (canManage) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _copyMondayToWeekdays,
                        child: const Text('Copy Monday to weekdays'),
                      ),
                      OutlinedButton(
                        onPressed: _setMondayToSaturday,
                        child: const Text('Set Monday-Saturday'),
                      ),
                      OutlinedButton(
                        onPressed: _closeSunday,
                        child: const Text('Close Sunday'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _PreviewCard(
                  summary: ClinicOperatingStatusService.weeklySummary(
                    ClinicWorkHoursConfig(
                      clinicId: config.clinicId,
                      timeZone: _timeZone,
                      isEnabled: _enabled,
                      days: _days,
                    ),
                  ),
                ),
                if (canManage) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(userSession),
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save work hours'),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _copyMondayToWeekdays() {
    final monday = _days.firstWhere((day) => day.weekday == 'monday');
    setState(() {
      _days = [
        for (final day in _days)
          if (day.weekday == 'saturday' || day.weekday == 'sunday')
            day
          else
            ClinicWorkDayConfig(
              weekday: day.weekday,
              isOpen: monday.isOpen,
              openingTime: monday.openingTime,
              closingTime: monday.closingTime,
              breakStart: monday.breakStart,
              breakEnd: monday.breakEnd,
            ),
      ];
    });
  }

  void _setMondayToSaturday() {
    setState(() {
      _days = [
        for (final day in _days)
          day.weekday == 'sunday'
              ? day
              : day.copyWith(
                  isOpen: true,
                  openingTime: day.openingTime ?? '08:00',
                  closingTime: day.closingTime ?? '18:00',
                ),
      ];
    });
  }

  void _closeSunday() {
    final index = _days.indexWhere((day) => day.weekday == 'sunday');
    if (index < 0) return;
    setState(() => _days[index] = _days[index].copyWith(isOpen: false));
  }

  Future<void> _save(UserSession session) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .updateClinicWorkHours(
            session: session,
            timeZone: _timeZone,
            isEnabled: _enabled,
            days: _days,
          );
      ref.invalidate(clinicWorkHoursProvider);
      ref.invalidate(clinicOperatingStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clinic work hours saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WorkDayEditor extends StatelessWidget {
  const _WorkDayEditor({
    required this.day,
    required this.enabled,
    required this.onChanged,
  });

  final ClinicWorkDayConfig day;
  final bool enabled;
  final ValueChanged<ClinicWorkDayConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final canEditTimes = enabled && day.isOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: AveraSpacing.cardGap),
      child: AveraSurfaceCard(
        outlined: true,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    clinicWeekdayLabels[day.weekday]!,
                    style: averaText(context).listItemTitle,
                  ),
                ),
                Text(
                  day.isOpen ? 'Open' : 'Closed',
                  style: averaText(context).caption,
                ),
                const SizedBox(width: AveraSpacing.compactRowGap),
                Switch.adaptive(
                  value: day.isOpen,
                  onChanged: enabled
                      ? (value) => onChanged(day.copyWith(isOpen: value))
                      : null,
                ),
              ],
            ),
            if (day.isOpen) ...[
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: 'Opens',
                      value: day.openingTime ?? '08:00',
                      enabled: canEditTimes,
                      onSelected: (value) =>
                          onChanged(day.copyWith(openingTime: value)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeField(
                      label: 'Closes',
                      value: day.closingTime ?? '18:00',
                      enabled: canEditTimes,
                      onSelected: (value) =>
                          onChanged(day.copyWith(closingTime: value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: canEditTimes ? () => _editBreak(context) : null,
                  icon: const Icon(Icons.coffee_outlined, size: 18),
                  label: Text(
                    day.breakStart == null
                        ? 'Add break'
                        : 'Break ${day.breakStart}-${day.breakEnd}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editBreak(BuildContext context) async {
    final start = await _pickTime(context, day.breakStart ?? '12:00');
    if (start == null) return;
    if (!context.mounted) return;
    final end = await _pickTime(context, day.breakEnd ?? '13:00');
    if (end == null) return;
    onChanged(day.copyWith(breakStart: start, breakEnd: end));
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: InkWell(
      onTap: enabled
          ? () async {
              final selected = await _pickTime(context, value);
              if (selected != null) onSelected(selected);
            }
          : null,
      child: Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 20,
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
          const SizedBox(width: AveraSpacing.compactRowGap),
          Expanded(
            child: Text(
              DateFormat(
                'HH:mm',
              ).format(DateFormat('HH:mm').parseStrict(value)),
              style: averaText(context).fieldValue.copyWith(
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _pickTime(BuildContext context, String stored) async {
  final parsed = DateFormat('HH:mm').parseStrict(stored);
  final selected = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: parsed.hour, minute: parsed.minute),
  );
  if (selected == null) return null;
  return '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.summary});
  final String summary;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    outlined: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preview', style: averaText(context).listItemTitle),
        const SizedBox(height: 8),
        Text(summary, style: averaText(context).listItemSubtitle),
      ],
    ),
  );
}

class _WorkHoursMessage extends StatelessWidget {
  const _WorkHoursMessage({
    required this.title,
    required this.message,
    this.onRetry,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_outlined, size: 42),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}
