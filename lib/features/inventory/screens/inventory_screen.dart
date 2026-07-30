import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.initialStatusFilter});

  final InventoryStatusFilter? initialStatusFilter;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String? _categoryId;
  String _query = '';
  InventoryStatusFilter _statusFilter = InventoryStatusFilter.all;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter ?? InventoryStatusFilter.all;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectStatusFilter(InventoryStatusFilter filter) {
    setState(() => _statusFilter = filter);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repository = ref.watch(clinicRepositoryProvider);
    final allowed = repository.permittedInventoryCategoryIds(session);
    return Scaffold(
      floatingActionButton: session.can(Permissions.inventoryCreate)
          ? FloatingActionButton.extended(
              onPressed: () => _showItemDialog(context, ref, session),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Inventory'),
            )
          : null,
      appBar: AppBar(title: const Text('Inventory')),
      body: StreamBuilder<List<InventoryItem>>(
        stream: repository.watchPermittedInventory(
          session,
          categoryId: _categoryId,
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Inventory is unavailable.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categoryItems = snapshot.data!;
          final today = DateTime.now();
          final low = categoryItems
              .where((item) => item.quantity <= item.minimumQuantity)
              .length;
          final expired = categoryItems
              .where((item) => item.expiryDate?.isBefore(today) ?? false)
              .length;
          final normalizedQuery = _query.trim().toLowerCase();
          final items = categoryItems
              .where(
                (item) => _statusFilter.matches(
                  quantity: item.quantity,
                  minimumQuantity: item.minimumQuantity,
                  expiryDate: item.expiryDate,
                  now: today,
                ),
              )
              .where(
                (item) =>
                    normalizedQuery.isEmpty ||
                    '${item.drugName} ${item.category} ${item.batchNumber ?? ''}'
                        .toLowerCase()
                        .contains(normalizedQuery),
              )
              .toList(growable: false);
          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search inventory',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              AveraLabeledFieldCard(
                label: 'Category',
                child: InkWell(
                  onTap: () => _selectCategory(context, allowed),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _categoryId == null
                              ? 'All Categories'
                              : InventoryCategories.byId(_categoryId)?.name ??
                                    'Category',
                          style: averaText(context).fieldValue,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SummaryStrip(
                total: categoryItems.length,
                low: low,
                expired: expired,
                selected: _statusFilter,
                onSelected: _selectStatusFilter,
              ),
              const SizedBox(height: 16),
              _FilterHeading(
                filter: _statusFilter,
                visibleCount: items.length,
                onClear: _statusFilter == InventoryStatusFilter.all
                    ? null
                    : () => _selectStatusFilter(InventoryStatusFilter.all),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                _InventoryMessage(
                  filter: _statusFilter,
                  hasSearch: normalizedQuery.isNotEmpty,
                  onClear: () => _selectStatusFilter(InventoryStatusFilter.all),
                )
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InventoryCard(
                      item: item,
                      canSeeCost: session.can(Permissions.inventoryCostView),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _selectCategory(
    BuildContext context,
    Set<String> allowed,
  ) async {
    final selection = await showModalBottomSheet<String?>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _CategorySheet(allowed: allowed, selected: _categoryId),
    );
    if (mounted) setState(() => _categoryId = selection);
  }

  Future<void> _showItemDialog(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    final name = TextEditingController();
    final quantity = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '5');
    final batch = TextEditingController();
    final selling = TextEditingController(text: '0');
    final cost = TextEditingController(text: '0');
    var categoryId = 'drugs';
    DateTime? expiry;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Inventory'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Item name'),
                ),
                DropdownButtonFormField<String>(
                  value: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final category in InventoryCategories.all.where(
                      (item) => ref
                          .read(clinicRepositoryProvider)
                          .permittedInventoryCategoryIds(session)
                          .contains(item.id),
                    ))
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => categoryId = value!),
                ),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum quantity',
                  ),
                ),
                TextField(
                  controller: batch,
                  decoration: const InputDecoration(labelText: 'Batch number'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    expiry == null
                        ? 'Expiry date'
                        : DateFormat.yMMMd().format(expiry!),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: expiry ?? DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => expiry = picked);
                  },
                ),
                TextField(
                  controller: selling,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Selling price (NGN)',
                  ),
                ),
                if (session.can(Permissions.inventoryCostView))
                  TextField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cost price (NGN)',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await ref
                      .read(clinicRepositoryProvider)
                      .saveInventoryItem(
                        session: session,
                        name: name.text,
                        categoryId: categoryId,
                        quantity: int.tryParse(quantity.text) ?? -1,
                        minimumQuantity: int.tryParse(minimum.text) ?? -1,
                        batchNumber: batch.text,
                        expiryDate: expiry,
                        sellingPrice: double.tryParse(selling.text) ?? -1,
                        buyingPrice: session.can(Permissions.inventoryCostView)
                            ? double.tryParse(cost.text)
                            : null,
                      );
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.allowed, required this.selected});
  final Set<String> allowed;
  final String? selected;
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final categories = InventoryCategories.all
        .where(
          (item) =>
              widget.allowed.contains(item.id) &&
              item.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Select Category', style: averaText(context).sectionTitle),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search categories',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('All Categories'),
            trailing: widget.selected == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return ListTile(
                  title: Text(category.name),
                  trailing: category.id == widget.selected
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, category.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.low,
    required this.expired,
    required this.selected,
    required this.onSelected,
  });
  final int total;
  final int low;
  final int expired;
  final InventoryStatusFilter selected;
  final ValueChanged<InventoryStatusFilter> onSelected;
  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Row(
      children: [
        Expanded(
          child: _SummaryValue(
            value: '$total',
            label: 'Items',
            selected: selected == InventoryStatusFilter.all,
            onTap: () => onSelected(InventoryStatusFilter.all),
          ),
        ),
        Expanded(
          child: _SummaryValue(
            value: '$low',
            label: 'Low stock',
            selected: selected == InventoryStatusFilter.lowStock,
            onTap: () => onSelected(InventoryStatusFilter.lowStock),
          ),
        ),
        Expanded(
          child: _SummaryValue(
            value: '$expired',
            label: 'Expired',
            selected: selected == InventoryStatusFilter.expired,
            onTap: () => onSelected(InventoryStatusFilter.expired),
          ),
        ),
      ],
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String value;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $value items${selected ? ', selected' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: averaText(
                  context,
                ).listItemTitle.copyWith(color: selected ? color : null),
              ),
              Text(label, style: averaText(context).caption),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterHeading extends StatelessWidget {
  const _FilterHeading({
    required this.filter,
    required this.visibleCount,
    this.onClear,
  });
  final InventoryStatusFilter filter;
  final int visibleCount;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final title = switch (filter) {
      InventoryStatusFilter.all => 'All Inventory',
      InventoryStatusFilter.lowStock => 'Low Stock',
      InventoryStatusFilter.expired => 'Expired Inventory',
    };
    final subtitle = switch (filter) {
      InventoryStatusFilter.all => '$visibleCount visible items',
      InventoryStatusFilter.lowStock =>
        '$visibleCount items require restocking',
      InventoryStatusFilter.expired => '$visibleCount expired items',
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: averaText(context).sectionLabel),
              Text(subtitle, style: averaText(context).caption),
            ],
          ),
        ),
        if (onClear != null)
          TextButton(onPressed: onClear, child: const Text('Clear filter')),
      ],
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.item, required this.canSeeCost});
  final InventoryItem item;
  final bool canSeeCost;
  @override
  Widget build(BuildContext context) {
    final expired = item.expiryDate?.isBefore(DateTime.now()) ?? false;
    final low = !expired && item.quantity <= item.minimumQuantity;
    final status = expired
        ? 'Expired'
        : item.quantity == 0
        ? 'Out of Stock'
        : low
        ? 'Low stock'
        : null;
    return AveraSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              expired ? Icons.timer_off_outlined : Icons.inventory_2_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.drugName, style: averaText(context).listItemTitle),
                Text(
                  '${item.category} / Qty ${item.quantity} / Min ${item.minimumQuantity}',
                  style: averaText(context).listItemSubtitle,
                ),
                Text(
                  'Batch ${item.batchNumber ?? '-'} / Exp ${item.expiryDate == null ? '-' : DateFormat.yMMMd().format(item.expiryDate!)}',
                  style: averaText(context).caption,
                ),
                if (item.isSellable)
                  Text(
                    formatNaira(item.sellingPrice),
                    style: averaText(context).caption,
                  ),
                if (canSeeCost)
                  Text(
                    'Cost: ${formatNaira(item.buyingPrice)}',
                    style: averaText(context).caption,
                  ),
              ],
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(label: Text(status)),
            ),
        ],
      ),
    );
  }
}

class _InventoryMessage extends StatelessWidget {
  const _InventoryMessage({
    required this.filter,
    required this.hasSearch,
    required this.onClear,
  });
  final InventoryStatusFilter filter;
  final bool hasSearch;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = hasSearch
        ? (
            'No matching Inventory items',
            'Try another search term or clear the active filter.',
          )
        : switch (filter) {
            InventoryStatusFilter.lowStock => (
              'No low-stock items',
              'All visible Inventory items are currently above their minimum quantities.',
            ),
            InventoryStatusFilter.expired => (
              'No expired items',
              'There are no expired Inventory items in this category.',
            ),
            InventoryStatusFilter.all => (
              'No Inventory items',
              'No permitted items match this category.',
            ),
          };
    return AveraSurfaceCard(
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: filter == InventoryStatusFilter.all
            ? null
            : TextButton(onPressed: onClear, child: const Text('Clear')),
      ),
    );
  }
}
