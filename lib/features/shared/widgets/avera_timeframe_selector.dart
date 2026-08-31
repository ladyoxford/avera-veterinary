import 'package:flutter/material.dart';

import '../../billing/models/revenue_period.dart';
import 'avera_ui.dart';

const selectableAveraTimeframes = <RevenuePeriod>[
  RevenuePeriod.oneDay,
  RevenuePeriod.threeDays,
  RevenuePeriod.sevenDays,
  RevenuePeriod.oneMonth,
  RevenuePeriod.threeMonths,
  RevenuePeriod.sixMonths,
  RevenuePeriod.oneYear,
  RevenuePeriod.threeYears,
  RevenuePeriod.tenYears,
  RevenuePeriod.allTime,
];

Future<RevenuePeriod?> showAveraTimeframePicker(
  BuildContext context,
  RevenuePeriod current, {
  required String description,
  String keyPrefix = 'timeframe',
}) {
  var pending = current;
  return showAveraActionSheet<RevenuePeriod>(
    context: context,
    title: 'Select Timeframe',
    description: description,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.count(
              key: Key('$keyPrefix-more-period-grid'),
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.25,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final period in selectableAveraTimeframes)
                  ChoiceChip(
                    key: Key('$keyPrefix-period-${period.apiValue}'),
                    label: SizedBox(
                      width: double.infinity,
                      child: Text(
                        period.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    selected: pending == period,
                    onSelected: (_) => setSheetState(() => pending = period),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: Key('apply-$keyPrefix-period'),
                onPressed: () => Navigator.of(sheetContext).pop(pending),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AveraTimeframeSelector extends StatelessWidget {
  const AveraTimeframeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onMore,
    this.keyPrefix = 'timeframe',
  });

  final RevenuePeriod selected;
  final ValueChanged<RevenuePeriod> onSelected;
  final VoidCallback onMore;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    key: Key('$keyPrefix-quick-period-row'),
    children: [
      for (final period in quickRevenuePeriods) ...[
        Expanded(
          child: _TimeframeButton(
            label: period.label,
            selected: selected == period,
            onTap: () => onSelected(period),
          ),
        ),
        const SizedBox(width: 6),
      ],
      Expanded(
        child: _TimeframeButton(
          key: Key('$keyPrefix-period-more'),
          label: 'More',
          selected: !quickRevenuePeriods.contains(selected),
          outlined: true,
          onTap: onMore,
        ),
      ),
    ],
  );
}

class _TimeframeButton extends StatelessWidget {
  const _TimeframeButton({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label report timeframe',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: outlined ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 2),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: outlined || selected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
