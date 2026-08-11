import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../navigation/clinic_activity_navigation.dart';
import '../widgets/avera_ui.dart';

enum _ActivityRange { all, today, yesterday, last7Days, last30Days, custom }

class ActivityHistoryScreen extends ConsumerStatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  ConsumerState<ActivityHistoryScreen> createState() =>
      _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends ConsumerState<ActivityHistoryScreen> {
  static const _pageSize = 50;
  final _search = TextEditingController();
  Timer? _debounce;
  _ActivityRange _range = _ActivityRange.all;
  String? _module;
  DateTimeRange? _customRange;
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = true;
  List<ClinicActivityTimelineEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  DateTimeRange? get _selectedRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_range) {
      _ActivityRange.today => DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      _ActivityRange.yesterday => DateTimeRange(
        start: today.subtract(const Duration(days: 1)),
        end: today,
      ),
      _ActivityRange.last7Days => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today.add(const Duration(days: 1)),
      ),
      _ActivityRange.last30Days => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today.add(const Duration(days: 1)),
      ),
      _ActivityRange.custom => _customRange,
      _ActivityRange.all => null,
    };
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() => _loading = true);
    try {
      final range = _selectedRange;
      final page = await ref
          .read(clinicRepositoryProvider)
          .getClinicActivityPage(
            limit: _pageSize,
            offset: reset ? 0 : _offset,
            from: range?.start,
            until: range?.end,
            module: _module,
            search: _search.text,
          );
      if (!mounted) return;
      setState(() {
        _events = reset ? page : [..._events, ...page];
        _offset = _events.length;
        _hasMore = page.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
    );
    if (range == null || !mounted) return;
    setState(() {
      _range = _ActivityRange.custom;
      _customRange = DateTimeRange(
        start: range.start,
        end: range.end.add(const Duration(days: 1)),
      );
    });
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activity History')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          Text('Activity History', style: averaText(context).pageTitle),
          const SizedBox(height: 6),
          Text(
            'Review clinic actions across patients, staff and operations.',
            style: averaText(context).pageSubtitle,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search clinic activity',
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => _load(reset: true),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final range in _ActivityRange.values)
                ChoiceChip(
                  label: Text(_rangeLabel(range)),
                  selected: _range == range,
                  onSelected: (_) async {
                    if (range == _ActivityRange.custom) {
                      await _chooseCustomRange();
                      return;
                    }
                    setState(() => _range = range);
                    await _load(reset: true);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ModuleFilter(
            value: _module,
            onChanged: (value) async {
              setState(() => _module = value);
              await _load(reset: true);
            },
          ),
          const SizedBox(height: 20),
          if (_events.isEmpty && !_loading)
            const _ActivityEmptyState()
          else
            ..._groupedRows(context),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_hasMore && !_loading)
            TextButton.icon(
              onPressed: () => _load(reset: false),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Load more activity'),
            ),
        ],
      ),
    ),
  );

  List<Widget> _groupedRows(BuildContext context) {
    final rows = <Widget>[];
    String? previousDay;
    for (var index = 0; index < _events.length; index++) {
      final event = _events[index];
      final day = DateFormat('yyyy-MM-dd').format(event.occurredAt);
      if (day != previousDay) {
        previousDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              _dayLabel(event.occurredAt),
              style: averaText(context).sectionLabel,
            ),
          ),
        );
      }
      rows.add(_ActivityHistoryRow(event: event));
      final next = index + 1 < _events.length ? _events[index + 1] : null;
      if (next != null &&
          DateFormat('yyyy-MM-dd').format(next.occurredAt) == day) {
        rows.add(const SizedBox(height: AveraSpacing.cardGap));
      }
    }
    return rows;
  }
}

class _ModuleFilter extends StatelessWidget {
  const _ModuleFilter({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;
  static const _modules = [
    'Schedule',
    'Vaccinations',
    'Consultations',
    'Inventory',
    'Billing',
    'Patients',
    'Staff',
    'Administration',
  ];

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    value: value,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Module'),
    items: [
      const DropdownMenuItem<String?>(value: null, child: Text('All Modules')),
      for (final module in _modules)
        DropdownMenuItem(value: module, child: Text(module)),
    ],
    onChanged: onChanged,
  );
}

class _ActivityHistoryRow extends StatelessWidget {
  const _ActivityHistoryRow({required this.event});
  final ClinicActivityTimelineEvent event;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(_iconFor(event.type))),
      title: Text(event.title, style: averaText(context).listItemTitle),
      subtitle: Text(
        '${_displayDescription(event.description)}\n${DateFormat.jm().format(event.occurredAt)}',
        style: averaText(context).listItemSubtitle,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openActivity(context, event),
    ),
  );
}

class _ActivityEmptyState extends StatelessWidget {
  const _ActivityEmptyState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(Icons.history_toggle_off_outlined, size: 40),
        SizedBox(height: 12),
        Text('No activity found'),
        SizedBox(height: 4),
        Text(
          'Try changing your date, module or search filters.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

String _rangeLabel(_ActivityRange range) => switch (range) {
  _ActivityRange.all => 'All Time',
  _ActivityRange.today => 'Today',
  _ActivityRange.yesterday => 'Yesterday',
  _ActivityRange.last7Days => 'Last 7 Days',
  _ActivityRange.last30Days => 'Last 30 Days',
  _ActivityRange.custom => 'Custom Range',
};

String _dayLabel(DateTime value) {
  final today = DateTime.now();
  final date = DateTime(value.year, value.month, value.day);
  final startToday = DateTime(today.year, today.month, today.day);
  if (date == startToday) return 'Today';
  if (date == startToday.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat.yMMMMd().format(value);
}

IconData _iconFor(String type) => type == 'vaccinationRecorded'
    ? Icons.vaccines_outlined
    : type.startsWith('appointment')
    ? Icons.event_available_outlined
    : Icons.history_rounded;

String _displayDescription(String value) => value.replaceAllMapped(
  RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?'),
  (match) {
    final date = DateTime.tryParse(match.group(0)!);
    return date == null
        ? match.group(0)!
        : DateFormat.yMMMMd().add_jm().format(date);
  },
);

void _openActivity(BuildContext context, ClinicActivityTimelineEvent event) {
  final route = clinicActivityRoute(event);
  if (route != null) {
    context.push(route);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity Details', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          Text(event.title, style: averaText(context).listItemTitle),
          const SizedBox(height: 6),
          Text(
            _displayDescription(event.description),
            style: averaText(context).listItemSubtitle,
          ),
        ],
      ),
    ),
  );
}
