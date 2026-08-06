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

  static const labels = <String>[
    'Overview',
    'Signalment',
    'Owner',
    'Medical History',
    'Consultations',
    'Vaccinations',
    'Laboratory',
    'Hospitalization',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return ChoiceChip(
            label: Text(labels[index]),
            selected: selected,
            onSelected: (_) => onSelected(index),
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
