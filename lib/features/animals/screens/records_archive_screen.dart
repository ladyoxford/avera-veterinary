import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/database/app_database.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../shared/widgets/avera_ui.dart';

class RecordsArchiveScreen extends ConsumerWidget {
  const RecordsArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records Archive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AveraPageHeader(
            title: 'Records Archive',
            subtitle: 'Review records removed from active clinic operations.',
          ),
          const SizedBox(height: 24),
          _ArchiveDestination(
            icon: Icons.pets_outlined,
            title: 'Animal Records',
            subtitle: 'Animals marked deceased or relocated',
            onTap: () => context.push('/records-archive/animals'),
          ),
          const SizedBox(height: 12),
          _ArchiveDestination(
            icon: Icons.business_center_outlined,
            title: 'Business Records',
            subtitle: 'Archived inventory and voided invoices',
            onTap: () => context.push('/records-archive/business'),
          ),
        ],
      ),
    );
  }
}

class BusinessRecordsArchiveScreen extends ConsumerWidget {
  const BusinessRecordsArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Business Records'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Inventory'),
              Tab(text: 'Invoices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ArchivedInventoryList(session: session),
            _VoidedInvoiceList(session: session),
          ],
        ),
      ),
    );
  }
}

class _ArchiveDestination extends StatelessWidget {
  const _ArchiveDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: averaText(context).listItemTitle),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _ArchivedInventoryList extends ConsumerWidget {
  const _ArchivedInventoryList({required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (BackendConfiguration.isConfigured) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: ref.read(clinicalRemoteDataSourceProvider).archivedInventory(),
        builder: (context, snapshot) =>
            _RemoteArchiveList(snapshot: snapshot, inventory: true),
      );
    }
    if (!session.can(Permissions.inventoryView)) {
      return const Center(
        child: Text('You do not have permission to view archived inventory.'),
      );
    }
    return StreamBuilder<List<InventoryItem>>(
      stream: ref
          .read(clinicRepositoryProvider)
          .watchArchivedInventory(session),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No archived inventory items.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return FutureBuilder<InventoryStockMovement?>(
              future: ref
                  .read(clinicRepositoryProvider)
                  .archivedInventoryMovement(session, item.id),
              builder: (context, movementSnapshot) {
                final movement = movementSnapshot.data;
                final outOfStock = movement?.movementType == 'OutOfStock';
                return _ArchiveCard(
                  title: item.drugName,
                  subtitle: [
                    item.genericName ?? item.brandName,
                    item.category,
                    'Stock ${item.quantity} ${item.baseUnitLabel}',
                    if (item.batchNumber != null) 'Batch ${item.batchNumber}',
                  ].whereType<String>().join(' | '),
                  badge: outOfStock ? 'OUT OF STOCK' : 'RETIRED',
                  warning: outOfStock,
                  date: movement?.createdAt ?? item.updatedAt,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VoidedInvoiceList extends ConsumerWidget {
  const _VoidedInvoiceList({required this.session});
  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (BackendConfiguration.isConfigured) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: ref.read(clinicalRemoteDataSourceProvider).archivedInvoices(),
        builder: (context, snapshot) =>
            _RemoteArchiveList(snapshot: snapshot, inventory: false),
      );
    }
    if (!session.can(Permissions.billingHistory)) {
      return const Center(
        child: Text('You do not have permission to view voided invoices.'),
      );
    }
    return StreamBuilder<List<BillingHistoryEntry>>(
      stream: ref.read(clinicRepositoryProvider).watchVoidedInvoices(session),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return const Center(child: Text('No voided invoices.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _ArchiveCard(
              title: entry.invoice.reference,
              subtitle:
                  '${entry.owner?.fullName ?? entry.invoice.clientNameSnapshot ?? entry.farm?.name ?? 'Client'} | ${session.clinic.currency} ${entry.invoice.total.toStringAsFixed(2)}${entry.invoice.voidReason == null ? '' : ' | ${entry.invoice.voidReason}'}',
              badge: 'VOIDED',
              date: entry.invoice.voidedAt ?? entry.invoice.updatedAt,
            );
          },
        );
      },
    );
  }
}

class _RemoteArchiveList extends StatelessWidget {
  const _RemoteArchiveList({required this.snapshot, required this.inventory});
  final AsyncSnapshot<List<Map<String, dynamic>>> snapshot;
  final bool inventory;

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: Text('Unable to load archived records: ${snapshot.error}'),
      );
    }
    final items = snapshot.data ?? const [];
    if (items.isEmpty) {
      return Center(
        child: Text(
          inventory ? 'No archived inventory items.' : 'No voided invoices.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        if (inventory) {
          final reason = '${item['archive_reason'] ?? 'Retired'}';
          final outOfStock = reason == 'OutOfStock';
          return _ArchiveCard(
            title: '${item['name'] ?? 'Inventory item'}',
            subtitle:
                '${item['category'] ?? ''} | Stock ${item['quantity'] ?? 0} | ${item['batch_number'] ?? 'No batch'}',
            badge: outOfStock ? 'OUT OF STOCK' : 'RETIRED',
            warning: outOfStock,
            date: DateTime.tryParse('${item['archived_at'] ?? ''}')?.toLocal(),
          );
        }
        return _ArchiveCard(
          title: '${item['invoice_number'] ?? 'Invoice'}',
          subtitle:
              '${item['owner_name'] ?? item['client_name_snapshot'] ?? item['farm_name'] ?? 'Client'} | ${item['total'] ?? 0}${item['void_reason'] == null ? '' : ' | ${item['void_reason']}'}',
          badge: 'VOIDED',
          date: DateTime.tryParse('${item['voided_at'] ?? ''}')?.toLocal(),
        );
      },
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    this.warning = false,
    this.date,
  });
  final String title;
  final String subtitle;
  final String badge;
  final bool warning;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? Colors.amber.shade800
        : Theme.of(context).colorScheme.error;
    return AveraSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: averaText(context).listItemTitle),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: averaText(context).listItemSubtitle),
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(
              'Archived ${DateFormat.yMMMd().add_jm().format(date!)}',
              style: averaText(context).caption,
            ),
          ],
        ],
      ),
    );
  }
}
