import 'package:flutter/material.dart';

/// The compact top-eight record strip for the local Medical File shell.
class PinnedRecordNavigation extends StatelessWidget {
  const PinnedRecordNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const records = <(int, String)>[
    (1, 'Signalment'),
    (2, 'Owner'),
    (3, 'Medical History'),
    (4, 'Consultations'),
    (5, 'Vaccinations'),
    (6, 'Laboratory'),
    (8, 'Surgery'),
    (7, 'Hospitalization'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final record = records[index];
          final selected = record.$1 == selectedIndex;
          return ChoiceChip(
            label: Text(record.$2),
            selected: selected,
            onSelected: (_) => onSelected(record.$1),
            selectedColor: scheme.primaryContainer,
            labelStyle: TextStyle(
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          );
        },
      ),
    );
  }
}
