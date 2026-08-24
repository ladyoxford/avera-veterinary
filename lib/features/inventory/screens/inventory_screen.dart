import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/inventory_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/identity_avatar_image.dart';
import '../widgets/inventory_item_dialog.dart';

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
    final remoteState = BackendConfiguration.isConfigured
        ? ref.watch(remoteInventoryListProvider)
        : null;
    return Scaffold(
      floatingActionButton: session.can(Permissions.inventoryCreate)
          ? FloatingActionButton.extended(
              onPressed: () => _showItemDialog(context, ref, session),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Inventory'),
            )
          : null,
      appBar: AppBar(title: const Text('Inventory')),
      body: remoteState == null
          ? StreamBuilder<List<InventoryItem>>(
              stream: repository.watchPermittedInventory(
                session,
                categoryId: _categoryId,
              ),
              builder: (context, snapshot) => _buildInventoryBody(
                context,
                session,
                allowed,
                items: (snapshot.data ?? const <InventoryItem>[])
                    .map(_InventoryDisplayItem.fromLocal)
                    .toList(),
                loading: !snapshot.hasData,
                error: snapshot.error,
              ),
            )
          : _buildInventoryBody(
              context,
              session,
              allowed,
              items: remoteState.items
                  .map(_InventoryDisplayItem.fromRemote)
                  .toList(),
              loading: remoteState.isLoading,
              error: remoteState.error,
              fromCache: remoteState.fromCache,
              onRetry: () =>
                  ref.read(remoteInventoryListProvider.notifier).refresh(),
            ),
    );
  }

  Widget _buildInventoryBody(
    BuildContext context,
    UserSession session,
    Set<String> allowed, {
    required List<_InventoryDisplayItem> items,
    required bool loading,
    Object? error,
    bool fromCache = false,
    Future<void> Function()? onRetry,
  }) {
    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Inventory is unavailable.'),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => onRetry(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      );
    }
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final categoryItems = items
        .where((item) => allowed.contains(item.categoryId))
        .where((item) => _categoryId == null || item.categoryId == _categoryId)
        .toList();
    final today = DateTime.now();
    final low = categoryItems
        .where((item) => item.quantity <= item.minimumQuantity)
        .length;
    final expired = categoryItems
        .where((item) => item.expiryDate?.isBefore(today) ?? false)
        .length;
    final expiring = categoryItems
        .where(
          (item) => InventoryStatusFilter.expiring.matches(
            quantity: item.quantity,
            minimumQuantity: item.minimumQuantity,
            expiryDate: item.expiryDate,
            now: today,
          ),
        )
        .length;
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleItems = categoryItems
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
              '${item.name} ${item.categoryName} ${item.manufacturer ?? ''} '
                      '${item.activeIngredient ?? ''} ${item.batchNumber ?? ''}'
                  .toLowerCase()
                  .contains(normalizedQuery),
        )
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: onRetry ?? () async {},
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          if (fromCache) ...[
            Row(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing saved inventory while the server reconnects.',
                    style: averaText(context).caption,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search medicines, brands, active ingredients...',
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          _InventoryCategorySelector(
            allowed: allowed,
            selected: _categoryId,
            onSelected: (value) => setState(() => _categoryId = value),
            onMore: () => _selectCategory(context, allowed),
          ),
          const SizedBox(height: 16),
          _SummaryStrip(
            total: categoryItems.length,
            low: low,
            expiring: expiring,
            expired: expired,
            selected: _statusFilter,
            onSelected: _selectStatusFilter,
          ),
          const SizedBox(height: 16),
          _FilterHeading(
            filter: _statusFilter,
            visibleCount: visibleItems.length,
            onClear: _statusFilter == InventoryStatusFilter.all
                ? null
                : () => _selectStatusFilter(InventoryStatusFilter.all),
          ),
          const SizedBox(height: 12),
          if (visibleItems.isEmpty)
            _InventoryMessage(
              filter: _statusFilter,
              hasSearch: normalizedQuery.isNotEmpty,
              onClear: () => _selectStatusFilter(InventoryStatusFilter.all),
            )
          else
            ...visibleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InventoryCard(
                  item: item,
                  canSeeCost: session.can(Permissions.inventoryCostView),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _InventoryProductDetailsScreen(
                        item: item,
                        catalogItems: categoryItems,
                        session: session,
                        onEdit: session.can(Permissions.inventoryEdit)
                            ? () => _showItemDialog(
                                context,
                                ref,
                                session,
                                initial: item.remote == null
                                    ? null
                                    : InventoryItemDraft.fromRemote(
                                        item.remote!,
                                      ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    UserSession session, {
    InventoryItemDraft? initial,
  }) async {
    final allowed = ref
        .read(clinicRepositoryProvider)
        .permittedInventoryCategoryIds(session);
    if (allowed.isEmpty) return;
    final saved = await showInventoryItemDialog(
      context: context,
      allowedCategoryIds: allowed,
      canSeeCost: session.can(Permissions.inventoryCostView),
      initial: initial,
      onSubmit: (draft) async {
        if (BackendConfiguration.isConfigured) {
          final controller = ref.read(remoteInventoryListProvider.notifier);
          if (draft.remoteId == null) {
            await controller.create(draft.toRemotePayload());
          } else {
            await controller.update(
              itemId: draft.remoteId!,
              payload: draft.toRemotePayload(),
            );
          }
          ref.invalidate(remoteDashboardProvider);
          return;
        }
        await ref
            .read(clinicRepositoryProvider)
            .saveInventoryItem(
              session: session,
              name: draft.name,
              categoryId: draft.categoryId,
              quantity: draft.quantity,
              minimumQuantity: draft.minimumQuantity,
              batchNumber: draft.batchNumber,
              expiryDate: draft.expiryDate,
              sellingPrice: draft.sellingPrice,
              buyingPrice: session.can(Permissions.inventoryCostView)
                  ? draft.buyingPrice
                  : null,
            );
      },
    );
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            initial == null
                ? 'Inventory item created.'
                : 'Inventory item updated.',
          ),
        ),
      );
    }
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

class _InventoryCategorySelector extends StatelessWidget {
  const _InventoryCategorySelector({
    required this.allowed,
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final Set<String> allowed;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final categories = InventoryCategories.all
        .where((category) => allowed.contains(category.id))
        .take(7)
        .toList(growable: false);
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final category in categories)
            _CategoryChip(
              label: category.name,
              selected: selected == category.id,
              onTap: () => onSelected(category.id),
            ),
          if (allowed.length > categories.length)
            _CategoryChip(
              label: 'More',
              selected:
                  selected != null &&
                  !categories.any((category) => category.id == selected),
              onTap: onMore,
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.low,
    required this.expiring,
    required this.expired,
    required this.selected,
    required this.onSelected,
  });
  final int total;
  final int low;
  final int expiring;
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
            value: '$expiring',
            label: 'Expiring',
            selected: selected == InventoryStatusFilter.expiring,
            onTap: () => onSelected(InventoryStatusFilter.expiring),
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
      InventoryStatusFilter.expiring => 'Expiring Soon',
      InventoryStatusFilter.expired => 'Expired Inventory',
    };
    final subtitle = switch (filter) {
      InventoryStatusFilter.all => '$visibleCount visible items',
      InventoryStatusFilter.lowStock =>
        '$visibleCount items require restocking',
      InventoryStatusFilter.expiring =>
        '$visibleCount items expire within 90 days',
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

class _InventoryDisplayItem {
  const _InventoryDisplayItem({
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.quantity,
    required this.minimumQuantity,
    required this.buyingPrice,
    required this.sellingPrice,
    required this.isSellable,
    this.batchNumber,
    this.expiryDate,
    this.remote,
    this.localId,
    this.manufacturer,
    this.supplier,
    this.baseUnitLabel = 'unit',
    this.activeIngredient,
    this.dosageAndRoute,
    this.withdrawalMeat,
    this.withdrawalMilk,
    this.withdrawalEggs,
    this.warnings,
    this.imagePath,
  });

  final String name;
  final String categoryId;
  final String categoryName;
  final int quantity;
  final int minimumQuantity;
  final double buyingPrice;
  final double sellingPrice;
  final bool isSellable;
  final String? batchNumber;
  final DateTime? expiryDate;
  final RemoteInventoryItem? remote;
  final int? localId;
  final String? manufacturer;
  final String? supplier;
  final String baseUnitLabel;
  final String? activeIngredient;
  final String? dosageAndRoute;
  final String? withdrawalMeat;
  final String? withdrawalMilk;
  final String? withdrawalEggs;
  final String? warnings;
  final String? imagePath;

  factory _InventoryDisplayItem.fromLocal(InventoryItem item) =>
      _InventoryDisplayItem(
        name: item.drugName,
        categoryId:
            item.categoryId ?? InventoryCategories.canonicalId(item.category),
        categoryName: item.category,
        quantity: item.quantity,
        minimumQuantity: item.minimumQuantity,
        buyingPrice: item.buyingPrice,
        sellingPrice: item.sellingPrice,
        isSellable: item.isSellable,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        localId: item.id,
        manufacturer: item.manufacturer,
        supplier: item.supplier,
        baseUnitLabel: item.baseUnitLabel,
        activeIngredient: item.activeIngredient,
        dosageAndRoute: item.dosageAndRoute,
        withdrawalMeat: item.withdrawalMeat,
        withdrawalMilk: item.withdrawalMilk,
        withdrawalEggs: item.withdrawalEggs,
        warnings: item.warnings,
        imagePath: item.imagePath,
      );

  factory _InventoryDisplayItem.fromRemote(RemoteInventoryItem item) =>
      _InventoryDisplayItem(
        name: item.name,
        categoryId: item.categoryId,
        categoryName:
            InventoryCategories.byId(item.categoryId)?.name ??
            item.categoryName,
        quantity: item.quantity,
        minimumQuantity: item.reorderLevel,
        buyingPrice: item.purchasePrice.toDouble(),
        sellingPrice: item.sellingPrice.toDouble(),
        isSellable: item.isSellable,
        batchNumber: item.batchNumber,
        expiryDate: item.expiryDate,
        manufacturer: item.manufacturer,
        supplier: item.supplier,
        baseUnitLabel: item.baseUnitLabel,
        activeIngredient: item.activeIngredient ?? item.genericName,
        dosageAndRoute: item.dosageAndRoute,
        withdrawalMeat: item.withdrawalMeat,
        withdrawalMilk: item.withdrawalMilk,
        withdrawalEggs: item.withdrawalEggs,
        warnings: item.warnings,
        remote: item,
      );
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.canSeeCost,
    this.onTap,
  });
  final _InventoryDisplayItem item;
  final bool canSeeCost;
  final VoidCallback? onTap;
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
    final brand = item.manufacturer?.trim();
    return AveraSurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AveraSpacing.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InventoryProductImage(
                name: item.name,
                imageReference: item.imagePath,
                width: 76,
                height: 92,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (brand?.isNotEmpty == true)
                      Text(
                        brand!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: averaText(context).sectionLabel,
                      ),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: averaText(context).listItemTitle,
                    ),
                    if (item.activeIngredient?.trim().isNotEmpty == true)
                      Text(
                        item.activeIngredient!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: averaText(context).caption,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatNaira(item.sellingPrice)} / ${item.baseUnitLabel}',
                      style: averaText(context).listItemTitle,
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _InventoryBadge(label: status ?? 'In stock'),
                        _InventoryBadge(label: item.categoryName),
                      ],
                    ),
                    Text(
                      '${item.quantity} ${item.baseUnitLabel}${item.quantity == 1 ? '' : 's'} available',
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
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryBadge extends StatelessWidget {
  const _InventoryBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label.toUpperCase(),
      style: averaText(context).caption.copyWith(fontSize: 10),
    ),
  );
}

class InventoryProductImage extends StatelessWidget {
  const InventoryProductImage({
    super.key,
    required this.name,
    this.imageReference,
    required this.width,
    required this.height,
  });

  final String name;
  final String? imageReference;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final reference = imageReference?.trim();
    final provider = reference == null || reference.isEmpty
        ? null
        : reference.startsWith('http')
        ? NetworkImage(reference) as ImageProvider<Object>
        : localIdentityImage(reference);
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.medication_liquid_outlined,
          size: height * .32,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
    return Semantics(
      image: true,
      label: '$name product image',
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: provider == null
              ? placeholder
              : Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
        ),
      ),
    );
  }
}

class _InventoryProductDetailsScreen extends ConsumerWidget {
  const _InventoryProductDetailsScreen({
    required this.item,
    required this.catalogItems,
    required this.session,
    this.onEdit,
  });

  final _InventoryDisplayItem item;
  final List<_InventoryDisplayItem> catalogItems;
  final UserSession session;
  final Future<void> Function()? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteId = item.remote?.id;
    final refreshedRemote = remoteId == null
        ? null
        : ref
              .watch(remoteInventoryListProvider)
              .items
              .where((candidate) => candidate.id == remoteId)
              .firstOrNull;
    final displayItem = refreshedRemote == null
        ? item
        : _InventoryDisplayItem.fromRemote(refreshedRemote);
    final localId = displayItem.localId;
    final sameManufacturer = catalogItems
        .where(
          (candidate) =>
              candidate.name != displayItem.name &&
              displayItem.manufacturer?.trim().isNotEmpty == true &&
              candidate.manufacturer?.trim().toLowerCase() ==
                  displayItem.manufacturer?.trim().toLowerCase(),
        )
        .toList(growable: false);
    final similar = catalogItems
        .where(
          (candidate) =>
              candidate.name != displayItem.name &&
              candidate.categoryId == displayItem.categoryId &&
              !sameManufacturer.contains(candidate),
        )
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          if (onEdit != null)
            TextButton.icon(
              onPressed: () async {
                await onEdit!();
                if (context.mounted) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          _ProductHero(item: displayItem),
          const SizedBox(height: 24),
          _ProductSectionTitle(
            title: 'Unit & Stock',
            action:
                (localId != null || remoteId != null) &&
                    session.can(Permissions.inventoryEdit)
                ? TextButton.icon(
                    onPressed: () => _configureUnits(
                      context,
                      ref,
                      localId: localId,
                      remote: refreshedRemote ?? displayItem.remote,
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Configure'),
                  )
                : null,
          ),
          if (remoteId != null)
            _UnitCards(
              item: displayItem,
              units: (refreshedRemote ?? displayItem.remote)!.productUnits
                  .map(
                    (unit) => _ProductUnitView(
                      id: unit.id,
                      label: unit.label,
                      conversionToBase: unit.conversionToBase,
                      sellingPrice: unit.sellingPrice.toDouble(),
                      isBase: unit.isBaseUnit,
                    ),
                  )
                  .toList(growable: false),
            )
          else if (localId == null)
            _UnitCards(
              item: displayItem,
              units: [
                _ProductUnitView(
                  label: displayItem.baseUnitLabel,
                  conversionToBase: 1,
                  sellingPrice: displayItem.sellingPrice,
                  isBase: true,
                ),
              ],
            )
          else
            StreamBuilder<List<ProductUnit>>(
              stream: ref
                  .read(clinicRepositoryProvider)
                  .watchProductUnits(
                    session: session,
                    inventoryItemId: localId,
                  ),
              builder: (context, snapshot) {
                final units = snapshot.data ?? const <ProductUnit>[];
                return _UnitCards(
                  item: displayItem,
                  units: units
                      .map(
                        (unit) => _ProductUnitView(
                          label: unit.unitLabel,
                          conversionToBase: unit.conversionToBase,
                          sellingPrice: unit.sellingPrice,
                          isBase: unit.isBaseUnit,
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          const SizedBox(height: 24),
          const _ProductSectionTitle(title: 'Important Stock Information'),
          _StockFacts(item: displayItem),
          const SizedBox(height: 24),
          const _ProductSectionTitle(title: 'Product Information'),
          _ProductInformation(item: displayItem),
          const SizedBox(height: 24),
          const _ProductSectionTitle(title: 'Supplier'),
          AveraSurfaceCard(
            child: Row(
              children: [
                CircleAvatar(
                  child: Text(
                    (displayItem.supplier ?? displayItem.manufacturer ?? 'S')
                        .trim()
                        .substring(0, 1)
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayItem.supplier ?? 'Supplier not set',
                        style: averaText(context).listItemTitle,
                      ),
                      Text(
                        displayItem.manufacturer ?? 'Manufacturer not set',
                        style: averaText(context).listItemSubtitle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                remoteId != null &&
                    displayItem.quantity <= displayItem.minimumQuantity &&
                    session.can(Permissions.inventoryAdjust)
                ? () =>
                      _requestRemoteReorder(context, ref, displayItem, remoteId)
                : null,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Request Reorder from Supplier'),
          ),
          if (sameManufacturer.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ProductSectionTitle(
              title: 'More from ${displayItem.manufacturer}',
            ),
            _ProductRecommendationRail(
              products: sameManufacturer,
              onTap: (product) => _openProduct(context, product),
            ),
          ],
          if (similar.isNotEmpty) ...[
            const SizedBox(height: 24),
            const _ProductSectionTitle(title: 'Similar Products'),
            _ProductRecommendationGrid(
              products: similar,
              onTap: (product) => _openProduct(context, product),
            ),
          ],
        ],
      ),
    );
  }

  void _openProduct(BuildContext context, _InventoryDisplayItem product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _InventoryProductDetailsScreen(
          item: product,
          catalogItems: catalogItems,
          session: session,
        ),
      ),
    );
  }

  Future<void> _configureUnits(
    BuildContext context,
    WidgetRef ref, {
    int? localId,
    RemoteInventoryItem? remote,
  }) async {
    final localUnits = localId == null
        ? const <ProductUnit>[]
        : await ref
              .read(clinicRepositoryProvider)
              .watchProductUnits(session: session, inventoryItemId: localId)
              .first;
    if (!context.mounted) return;
    final result = await showDialog<List<_ProductUnitView>>(
      context: context,
      builder: (_) => _ProductUnitsDialog(
        initial: remote != null
            ? remote.productUnits
                  .map(
                    (unit) => _ProductUnitView(
                      id: unit.id,
                      label: unit.label,
                      conversionToBase: unit.conversionToBase,
                      sellingPrice: unit.sellingPrice.toDouble(),
                      isBase: unit.isBaseUnit,
                    ),
                  )
                  .toList()
            : localUnits
                  .map(
                    (unit) => _ProductUnitView(
                      label: unit.unitLabel,
                      conversionToBase: unit.conversionToBase,
                      sellingPrice: unit.sellingPrice,
                      isBase: unit.isBaseUnit,
                    ),
                  )
                  .toList(),
      ),
    );
    if (result == null) return;
    if (remote != null) {
      await ref
          .read(remoteInventoryListProvider.notifier)
          .replaceUnits(
            itemId: remote.id,
            units: [
              for (final unit in result)
                {
                  if (unit.id != null) 'productUnitId': unit.id,
                  'unitLabel': unit.label,
                  'conversionToBase': unit.conversionToBase,
                  'sellingPrice': unit.sellingPrice,
                  'isBaseUnit': unit.isBase,
                },
            ],
          );
    } else if (localId != null) {
      await ref
          .read(clinicRepositoryProvider)
          .replaceProductUnits(
            session: session,
            inventoryItemId: localId,
            units: [
              for (final unit in result)
                (
                  label: unit.label,
                  conversionToBase: unit.conversionToBase,
                  sellingPrice: unit.sellingPrice,
                  isBase: unit.isBase,
                ),
            ],
          );
    }
  }

  Future<void> _requestRemoteReorder(
    BuildContext context,
    WidgetRef ref,
    _InventoryDisplayItem item,
    String remoteId,
  ) async {
    final quantity = (item.minimumQuantity - item.quantity)
        .clamp(1, 100000000)
        .toInt();
    try {
      await ref
          .read(remoteInventoryListProvider.notifier)
          .requestReorder(itemId: remoteId, requestedQuantity: quantity);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reorder request sent to ${item.supplier}.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The reorder request could not be sent.')),
      );
    }
  }
}

class _ProductHero extends StatelessWidget {
  const _ProductHero({required this.item});
  final _InventoryDisplayItem item;

  @override
  Widget build(BuildContext context) {
    final expired = item.expiryDate?.isBefore(DateTime.now()) ?? false;
    final low = !expired && item.quantity <= item.minimumQuantity;
    return AveraSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: averaText(context).pageTitle),
          const SizedBox(height: 4),
          Text(
            'Brand: ${item.manufacturer?.trim().isNotEmpty == true ? item.manufacturer : 'Not recorded'}',
            style: averaText(context).listItemSubtitle,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _InventoryBadge(
                label: expired
                    ? 'Expired'
                    : low
                    ? 'Low stock'
                    : 'In stock',
              ),
              _InventoryBadge(label: item.categoryName),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: InventoryProductImage(
              name: item.name,
              imageReference: item.imagePath,
              width: double.infinity,
              height: 220,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            formatNaira(item.sellingPrice),
            style: averaText(context).pageTitle,
          ),
          Text(
            '${formatNaira(item.sellingPrice)} per ${item.baseUnitLabel}',
            style: averaText(context).caption,
          ),
        ],
      ),
    );
  }
}

class _ProductSectionTitle extends StatelessWidget {
  const _ProductSectionTitle({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: averaText(context).sectionTitle)),
      if (action != null) action!,
    ],
  );
}

class _ProductUnitView {
  const _ProductUnitView({
    this.id,
    required this.label,
    required this.conversionToBase,
    required this.sellingPrice,
    required this.isBase,
  });
  final String? id;
  final String label;
  final int conversionToBase;
  final double sellingPrice;
  final bool isBase;
}

class _UnitCards extends StatelessWidget {
  const _UnitCards({required this.item, required this.units});
  final _InventoryDisplayItem item;
  final List<_ProductUnitView> units;

  @override
  Widget build(BuildContext context) {
    final resolved = units.isEmpty
        ? [
            _ProductUnitView(
              label: item.baseUnitLabel,
              conversionToBase: 1,
              sellingPrice: item.sellingPrice,
              isBase: true,
            ),
          ]
        : units;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < 430
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final unit in resolved)
              SizedBox(
                width: width,
                child: AveraSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${unit.label}${unit.isBase ? ' (base)' : ''}',
                        style: averaText(context).listItemTitle,
                      ),
                      Text(formatNaira(unit.sellingPrice)),
                      Text(
                        '${ClinicRepository.displayedStockForUnit(baseStock: item.quantity, conversionToBase: unit.conversionToBase)} in stock',
                        style: averaText(context).listItemSubtitle,
                      ),
                      if (!unit.isBase)
                        Text(
                          '1 ${unit.label} = ${unit.conversionToBase} ${item.baseUnitLabel}',
                          style: averaText(context).caption,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StockFacts extends StatelessWidget {
  const _StockFacts({required this.item});
  final _InventoryDisplayItem item;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Wrap(
      spacing: 28,
      runSpacing: 18,
      children: [
        _Fact('CURRENT STOCK', '${item.quantity} ${item.baseUnitLabel}'),
        _Fact('REORDER LEVEL', '${item.minimumQuantity} ${item.baseUnitLabel}'),
        _Fact('BATCH NUMBER', item.batchNumber ?? 'Not set'),
        _Fact(
          'EXPIRY DATE',
          item.expiryDate == null
              ? 'Not set'
              : DateFormat.yMMMd().format(item.expiryDate!),
        ),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: averaText(context).caption),
        const SizedBox(height: 4),
        Text(value, style: averaText(context).listItemTitle),
      ],
    ),
  );
}

class _ProductInformation extends StatelessWidget {
  const _ProductInformation({required this.item});
  final _InventoryDisplayItem item;

  @override
  Widget build(BuildContext context) {
    final withdrawals = <String>[
      if (item.withdrawalMeat?.trim().isNotEmpty ?? false)
        'Meat: ${item.withdrawalMeat}',
      if (item.withdrawalMilk?.trim().isNotEmpty ?? false)
        'Milk: ${item.withdrawalMilk}',
      if (item.withdrawalEggs?.trim().isNotEmpty ?? false)
        'Eggs: ${item.withdrawalEggs}',
    ];
    return AveraSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _ProductInfoTile(
            title: 'General Information',
            icon: Icons.info_outline_rounded,
            initiallyExpanded: true,
            value:
                '${item.name} is listed under ${item.categoryName}. '
                'Stock and selling units are managed from this clinic inventory record.',
          ),
          const Divider(height: 1),
          _ProductInfoTile(
            title: 'Active Ingredients',
            icon: Icons.science_outlined,
            value: item.activeIngredient,
          ),
          const Divider(height: 1),
          _ProductInfoTile(
            title: 'Dosage & Directions',
            icon: Icons.medication_outlined,
            value: item.dosageAndRoute,
          ),
          const Divider(height: 1),
          _ProductInfoTile(
            title: 'Withdrawal Period',
            icon: Icons.schedule_outlined,
            value: withdrawals.isEmpty ? null : withdrawals.join('\n'),
          ),
          const Divider(height: 1),
          _ProductInfoTile(
            title: 'Warnings',
            icon: Icons.warning_amber_rounded,
            value: item.warnings,
          ),
          const Divider(height: 1),
          const _ProductInfoTile(
            title: 'Storage',
            icon: Icons.inventory_2_outlined,
          ),
        ],
      ),
    );
  }
}

class _ProductInfoTile extends StatelessWidget {
  const _ProductInfoTile({
    required this.title,
    required this.icon,
    this.value,
    this.initiallyExpanded = false,
  });
  final String title;
  final IconData icon;
  final String? value;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    initiallyExpanded: initiallyExpanded,
    leading: Icon(icon),
    title: Text(title, style: averaText(context).listItemTitle),
    childrenPadding: const EdgeInsets.fromLTRB(56, 0, 20, 18),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          value?.trim().isNotEmpty == true ? value! : 'Not recorded',
          style: averaText(context).listItemSubtitle,
        ),
      ),
    ],
  );
}

class _ProductRecommendationRail extends StatelessWidget {
  const _ProductRecommendationRail({
    required this.products,
    required this.onTap,
  });
  final List<_InventoryDisplayItem> products;
  final ValueChanged<_InventoryDisplayItem> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 238,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) => SizedBox(
        width: 174,
        child: _ProductRecommendationCard(
          product: products[index],
          onTap: () => onTap(products[index]),
        ),
      ),
    ),
  );
}

class _ProductRecommendationGrid extends StatelessWidget {
  const _ProductRecommendationGrid({
    required this.products,
    required this.onTap,
  });
  final List<_InventoryDisplayItem> products;
  final ValueChanged<_InventoryDisplayItem> onTap;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: products.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      mainAxisExtent: 238,
    ),
    itemBuilder: (context, index) => _ProductRecommendationCard(
      product: products[index],
      onTap: () => onTap(products[index]),
    ),
  );
}

class _ProductRecommendationCard extends StatelessWidget {
  const _ProductRecommendationCard({
    required this.product,
    required this.onTap,
  });
  final _InventoryDisplayItem product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InventoryProductImage(
              name: product.name,
              imageReference: product.imagePath,
              width: double.infinity,
              height: 90,
            ),
            const SizedBox(height: 8),
            Text(
              product.manufacturer?.toUpperCase() ?? product.categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: averaText(context).caption,
            ),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: averaText(context).listItemTitle.copyWith(fontSize: 14),
            ),
            const Spacer(),
            Text(
              formatNaira(product.sellingPrice),
              style: averaText(context).listItemTitle.copyWith(fontSize: 14),
            ),
            Text(
              product.quantity > 0 ? 'IN STOCK' : 'OUT OF STOCK',
              style: averaText(context).caption,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProductUnitsDialog extends StatefulWidget {
  const _ProductUnitsDialog({required this.initial});
  final List<_ProductUnitView> initial;

  @override
  State<_ProductUnitsDialog> createState() => _ProductUnitsDialogState();
}

class _ProductUnitsDialogState extends State<_ProductUnitsDialog> {
  late List<_ProductUnitView> units = [...widget.initial];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Product Units'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < units.length; index++)
              ListTile(
                title: Text(units[index].label),
                subtitle: Text(
                  '${units[index].conversionToBase} base units / ${formatNaira(units[index].sellingPrice)}',
                ),
                leading: Icon(
                  units[index].isBase
                      ? Icons.check_circle_rounded
                      : Icons.inventory_2_outlined,
                ),
                trailing: units[index].isBase
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => units.removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            OutlinedButton.icon(
              onPressed: _addUnit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add packaging unit'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, units),
        child: const Text('Save'),
      ),
    ],
  );

  Future<void> _addUnit() async {
    final label = TextEditingController();
    final conversion = TextEditingController();
    final price = TextEditingController();
    final result = await showDialog<_ProductUnitView>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add packaging unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Unit label'),
            ),
            TextField(
              controller: conversion,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Base units per package',
              ),
            ),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Selling price'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsedConversion = int.tryParse(conversion.text.trim());
              final parsedPrice = double.tryParse(price.text.trim());
              if (label.text.trim().isEmpty ||
                  parsedConversion == null ||
                  parsedConversion <= 1 ||
                  parsedPrice == null ||
                  parsedPrice < 0) {
                return;
              }
              Navigator.pop(
                context,
                _ProductUnitView(
                  label: label.text.trim(),
                  conversionToBase: parsedConversion,
                  sellingPrice: parsedPrice,
                  isBase: false,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    label.dispose();
    conversion.dispose();
    price.dispose();
    if (result != null && mounted) setState(() => units.add(result));
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
            InventoryStatusFilter.expiring => (
              'No items expiring soon',
              'There are no Inventory items expiring within the next 90 days.',
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
