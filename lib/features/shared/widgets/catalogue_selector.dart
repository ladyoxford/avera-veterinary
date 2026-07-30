import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'avera_ui.dart';

class CataloguePickerOption {
  const CataloguePickerOption({
    required this.id,
    required this.title,
    this.subtitle,
    this.category,
    this.searchAliases = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? category;
  final List<String> searchAliases;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        title.toLowerCase().contains(normalized) ||
        (subtitle?.toLowerCase().contains(normalized) ?? false) ||
        (category?.toLowerCase().contains(normalized) ?? false) ||
        searchAliases.any((alias) => alias.toLowerCase().contains(normalized));
  }
}

Future<String?> showSearchableCatalogueSelector({
  required BuildContext context,
  required String title,
  required List<CataloguePickerOption> options,
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _CatalogueSheetViewport(
      child: SearchableCatalogueSheet(
        title: title,
        options: options,
        selectedId: selectedId,
      ),
    ),
  );
}

Future<Set<String>?> showMultiSearchableCatalogueSelector({
  required BuildContext context,
  required String title,
  required List<CataloguePickerOption> options,
  required Set<String> selectedIds,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _CatalogueSheetViewport(
      child: AveraMultiSelectCatalogueSheet(
        title: title,
        options: options,
        selectedIds: selectedIds,
      ),
    ),
  );
}

/// Keeps catalogue controls above the Android navigation area and shrinks
/// safely when the search keyboard is visible.
class _CatalogueSheetViewport extends StatelessWidget {
  const _CatalogueSheetViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: FractionallySizedBox(
      heightFactor: .90,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AveraSpacing.cardRadius),
        ),
        child: child,
      ),
    ),
  );
}

class SearchableCatalogueSheet extends StatefulWidget {
  const SearchableCatalogueSheet({
    super.key,
    required this.title,
    required this.options,
    this.selectedId,
  });

  final String title;
  final List<CataloguePickerOption> options;
  final String? selectedId;

  @override
  State<SearchableCatalogueSheet> createState() =>
      _SearchableCatalogueSheetState();
}

class _SearchableCatalogueSheetState extends State<SearchableCatalogueSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where((option) => option.matches(_query))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        12,
        AveraSpacing.pageHorizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CatalogueDragHandle(),
          const SizedBox(height: AveraSpacing.compactRowGap),
          Text(widget.title, style: averaText(context).pageTitle),
          const SizedBox(height: AveraSpacing.cardGap),
          TextField(
            key: const Key('catalogue-search-field'),
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          Expanded(
            child: _CatalogueOptionList(
              options: options,
              selectedIds: {if (widget.selectedId != null) widget.selectedId!},
              onTap: (id) => Navigator.pop(context, id),
            ),
          ),
        ],
      ),
    );
  }
}

class AveraMultiSelectCatalogueSheet extends StatefulWidget {
  const AveraMultiSelectCatalogueSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selectedIds,
  });

  final String title;
  final List<CataloguePickerOption> options;
  final Set<String> selectedIds;

  @override
  State<AveraMultiSelectCatalogueSheet> createState() =>
      _AveraMultiSelectCatalogueSheetState();
}

class _AveraMultiSelectCatalogueSheetState
    extends State<AveraMultiSelectCatalogueSheet> {
  late Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.selectedIds};
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options
        .where((option) => option.matches(_query))
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AveraSpacing.pageHorizontalPadding,
        12,
        AveraSpacing.pageHorizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CatalogueDragHandle(),
          const SizedBox(height: AveraSpacing.compactRowGap),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: averaText(context).pageTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AveraSpacing.compactRowGap),
              Text(
                '${_selectedIds.length} selected',
                style: averaText(context).caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AveraSpacing.cardGap),
          Expanded(
            child: _CatalogueOptionList(
              options: options,
              selectedIds: _selectedIds,
              multiSelect: true,
              onTap: (id) => setState(() {
                _selectedIds.contains(id)
                    ? _selectedIds.remove(id)
                    : _selectedIds.add(id);
              }),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(
                top: AveraSpacing.cardGap,
                bottom: AveraSpacing.compactRowGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          key: const Key('catalogue-clear-selection'),
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : () => setState(_selectedIds.clear),
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: AveraSpacing.compactRowGap),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('catalogue-cancel-selection'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AveraSpacing.compactRowGap),
                  FilledButton(
                    key: const Key('catalogue-apply-selection'),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => Navigator.of(context).pop({..._selectedIds}),
                    child: Text(
                      _selectedIds.isEmpty
                          ? 'Select at least one'
                          : 'Apply Selection (${_selectedIds.length})',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogueDragHandle extends StatelessWidget {
  const _CatalogueDragHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _CatalogueOptionList extends StatelessWidget {
  const _CatalogueOptionList({
    required this.options,
    required this.selectedIds,
    required this.onTap,
    this.multiSelect = false,
  });

  final List<CataloguePickerOption> options;
  final Set<String> selectedIds;
  final ValueChanged<String> onTap;
  final bool multiSelect;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Center(
        child: Text(
          'No matching options.',
          style: averaText(context).listItemSubtitle,
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: options.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final option = options[index];
        final previousCategory = index == 0
            ? null
            : options[index - 1].category;
        final showCategory =
            option.category != null && option.category != previousCategory;
        final selected = selectedIds.contains(option.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCategory)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                child: Text(
                  option.category!.toUpperCase(),
                  style: averaText(context).sectionLabel,
                ),
              ),
            ListTile(
              key: Key('catalogue-option-${option.id}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              title: Text(
                option.title,
                style: averaText(context).listItemTitle,
              ),
              subtitle: option.subtitle == null
                  ? null
                  : Text(
                      option.subtitle!,
                      style: averaText(context).listItemSubtitle,
                    ),
              trailing: Icon(
                multiSelect
                    ? selected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded
                    : selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              onTap: () => onTap(option.id),
            ),
          ],
        );
      },
    );
  }
}
