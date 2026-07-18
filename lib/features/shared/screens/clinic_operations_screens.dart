import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/feature_gate_service.dart';
import '../../animals/screens/animal_profile_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final services = _services
        .where(
          (service) =>
              session == null ||
              service.permission == null ||
              session.can(service.permission!),
        )
        .where(
          (service) =>
              service.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final vera = services.where((service) => service.featured).firstOrNull;
    final pinned = services.where((service) => service.pinned).take(8).toList();
    final groups = <String, List<_ClinicService>>{};
    for (final service in services.where(
      (service) => !service.pinned && !service.featured,
    )) {
      (groups[service.group] ??= []).add(service);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          Text(
            'Clinic tools and records',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (vera != null) ...[
            const SizedBox(height: 20),
            Text('Featured', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            _VeraFeaturedCard(service: vera),
          ],
          const SizedBox(height: 18),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search clinic tools',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Pinned Services',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520
                  ? 4
                  : constraints.maxWidth >= 360
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pinned.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                  childAspectRatio: columns >= 4 ? .95 : 1.06,
                ),
                itemBuilder: (context, index) =>
                    _PinnedServiceTile(service: pinned[index]),
              );
            },
          ),
          for (final group in groups.entries) ...[
            const SizedBox(height: 30),
            Text(group.key, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final service in group.value) _ServiceRow(service: service),
          ],
          if (services.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 36),
              child: _OperationsEmpty(
                message: 'No clinic tools match your search.',
              ),
            ),
        ],
      ),
    );
  }
}

class ClinicVaccineScheduleScreen extends ConsumerStatefulWidget {
  const ClinicVaccineScheduleScreen({super.key});
  @override
  ConsumerState<ClinicVaccineScheduleScreen> createState() =>
      _ClinicVaccineScheduleScreenState();
}

class _ClinicVaccineScheduleScreenState
    extends ConsumerState<ClinicVaccineScheduleScreen> {
  String _filter = 'All';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session != null && !session.can(Permissions.vaccinationsView)) {
      return const _OperationsDenied();
    }
    final formatter = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(title: const Text('Vaccine Schedule')),
      floatingActionButton: session?.can(Permissions.vaccinationsAdd) == true
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/vaccinations'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Record Vaccination'),
            )
          : null,
      body: StreamBuilder<List<ClinicVaccinationRecord>>(
        stream: ref.read(clinicRepositoryProvider).watchClinicVaccinations(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data!.where((record) {
            final status = _vaccineStatus(record.vaccination);
            final matchFilter = _filter == 'All' || status == _filter;
            final needle =
                '${record.animal.animalName} ${record.animal.hospitalNumber} ${record.owner.fullName} ${record.vaccination.vaccine}'
                    .toLowerCase();
            return matchFilter && needle.contains(_query.toLowerCase());
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search patients or vaccines',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      ['All', 'Due Today', 'Upcoming', 'Overdue', 'Completed']
                          .map(
                            (value) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(value),
                                selected: _filter == value,
                                onSelected: (_) =>
                                    setState(() => _filter = value),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              const SizedBox(height: 18),
              if (records.isEmpty)
                const _OperationsEmpty(
                  message: 'No vaccination records match these filters.',
                ),
              for (final record in records)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AnimalProfileScreen(
                          animalId: record.animal.id,
                          initialTab: 5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PatientAvatar(
                            name: record.animal.animalName,
                            photo: record.animal.photo,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.animal.animalName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${record.animal.hospitalNumber} • ${record.animal.species}${record.animal.breed == null ? '' : ' • ${record.animal.breed}'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  record.vaccination.vaccine,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${record.owner.fullName} • ${record.owner.phone}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Given: ${formatter.format(record.vaccination.dateGiven)}',
                                    ),
                                    Text(
                                      record.vaccination.nextDueDate == null
                                          ? 'No next due date'
                                          : 'Due: ${formatter.format(record.vaccination.nextDueDate!)}',
                                    ),
                                    if (record.vaccination.batchNumber != null)
                                      Text(
                                        'Batch: ${record.vaccination.batchNumber}',
                                      ),
                                    if (record.vaccination.manufacturer != null)
                                      Text(record.vaccination.manufacturer!),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _VaccineStatusBadge(
                            status: _vaccineStatus(record.vaccination),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ClinicOperationsPlaceholderScreen extends StatelessWidget {
  const ClinicOperationsPlaceholderScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });
  final String title;
  final String description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _PinnedServiceTile extends ConsumerWidget {
  const _PinnedServiceTile({required this.service});
  final _ClinicService service;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = _isFeatureLocked(ref, service);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(service.route),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  locked ? Icons.lock_outline_rounded : service.icon,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                service.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceRow extends ConsumerWidget {
  const _ServiceRow({required this.service});
  final _ClinicService service;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = _isFeatureLocked(ref, service);
    return Card(
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            locked ? Icons.lock_outline_rounded : service.icon,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(service.title),
        subtitle: Text(
          locked
              ? 'Requires ${FeatureGateService.entitlement(service.feature!).minimumPlan.label}'
              : service.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: locked
            ? const Icon(Icons.lock_outline_rounded)
            : const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(service.route),
      ),
    );
  }
}

class _ClinicService {
  const _ClinicService(
    this.title,
    this.description,
    this.icon,
    this.route,
    this.group, {
    this.permission,
    this.feature,
    this.pinned = false,
    this.featured = false,
  });
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final String group;
  final String? permission;
  final AveraFeature? feature;
  final bool pinned;
  final bool featured;
}

class _VeraFeaturedCard extends ConsumerWidget {
  const _VeraFeaturedCard({required this.service});
  final _ClinicService service;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final locked = _isFeatureLocked(ref, service);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => context.push(service.route),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primaryContainer, colors.secondaryContainer],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : Icons.account_tree_rounded,
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vera',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Veterinary Clinical Intelligence',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      locked
                          ? 'Requires ${FeatureGateService.entitlement(service.feature!).minimumPlan.label}'
                          : 'Ask clinical questions, analyse cases and review treatments.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

const _services = <_ClinicService>[
  _ClinicService(
    'Vera',
    'Veterinary Clinical Intelligence',
    Icons.account_tree_rounded,
    '/vera',
    'Featured',
    feature: AveraFeature.vera,
    featured: true,
  ),
  _ClinicService(
    'Vaccine Schedule',
    'Due, upcoming and completed vaccinations',
    Icons.vaccines_outlined,
    '/operations/vaccines',
    'Clinical Operations',
    permission: Permissions.vaccinationsView,
    feature: AveraFeature.vaccinations,
    pinned: true,
  ),
  _ClinicService(
    'Laboratory',
    'Requests, samples and results across the clinic',
    Icons.science_outlined,
    '/operations/laboratory',
    'Clinical Operations',
    permission: Permissions.laboratoryView,
    feature: AveraFeature.laboratory,
    pinned: true,
  ),
  _ClinicService(
    'Hospitalization',
    'Current admissions and treatment plans',
    Icons.local_hospital_outlined,
    '/operations/hospitalization',
    'Clinical Operations',
    permission: Permissions.consultationsView,
    feature: AveraFeature.hospitalization,
    pinned: true,
  ),
  _ClinicService(
    'Treatment Board',
    'Treatments due across wards and patients',
    Icons.view_kanban_outlined,
    '/operations/treatment-board',
    'Clinical Operations',
    permission: Permissions.consultationsView,
    feature: AveraFeature.treatmentBoard,
    pinned: true,
  ),
  _ClinicService(
    'Surgery',
    'Scheduled and completed surgical cases',
    Icons.medical_services_outlined,
    '/operations/surgery',
    'Clinical Operations',
    permission: Permissions.consultationsView,
    feature: AveraFeature.surgery,
  ),
  _ClinicService(
    'Prescriptions',
    'Active and dispensed prescriptions',
    Icons.medication_outlined,
    '/operations/prescriptions',
    'Clinical Operations',
    permission: Permissions.consultationsView,
    feature: AveraFeature.prescriptions,
  ),
  _ClinicService(
    'Imaging',
    'Diagnostic imaging requests and reports',
    Icons.image_search_outlined,
    '/operations/imaging',
    'Clinical Operations',
    permission: Permissions.laboratoryView,
    feature: AveraFeature.imaging,
  ),
  _ClinicService(
    'Medical Documents',
    'Clinical documents and attachments',
    Icons.description_outlined,
    '/operations/documents',
    'Clinical Operations',
    permission: Permissions.patientsView,
    feature: AveraFeature.documents,
  ),
  _ClinicService(
    'Inventory',
    'Stock, low quantities and product usage',
    Icons.inventory_2_outlined,
    '/inventory',
    'Practice Operations',
    permission: Permissions.inventoryView,
    feature: AveraFeature.inventory,
    pinned: true,
  ),
  _ClinicService(
    'Expired Products',
    'Products requiring inventory attention',
    Icons.warning_amber_rounded,
    '/inventory',
    'Practice Operations',
    permission: Permissions.inventoryView,
  ),
  _ClinicService(
    'Billing',
    'Invoices, payments and balances',
    Icons.receipt_long_outlined,
    '/billing',
    'Finance',
    permission: Permissions.billingView,
    feature: AveraFeature.billing,
    pinned: true,
  ),
  _ClinicService(
    'Reports',
    'Clinical and operational reporting',
    Icons.analytics_outlined,
    '/reports',
    'Reports and Analytics',
    permission: Permissions.reportsExport,
    feature: AveraFeature.reports,
    pinned: true,
  ),
  _ClinicService(
    'Schedule',
    'Schedule and clinic visit list',
    Icons.calendar_month_outlined,
    '/appointments',
    'Client Engagement',
    permission: Permissions.appointmentsView,
    feature: AveraFeature.schedule,
  ),
  _ClinicService(
    'Notifications',
    'Clinical and operational notices',
    Icons.notifications_none_rounded,
    '/notifications',
    'Client Engagement',
  ),
  _ClinicService(
    'Users',
    'Clinic staff and access management',
    Icons.people_outline_rounded,
    '/administration/users',
    'Administration',
    permission: Permissions.usersView,
  ),
  _ClinicService(
    'Administration',
    'Clinic settings, audit logs and security',
    Icons.admin_panel_settings_outlined,
    '/administration',
    'Administration',
    permission: Permissions.usersView,
  ),
  _ClinicService(
    'Backup & Restore',
    'Clinic data backup operations',
    Icons.backup_outlined,
    '/backup',
    'Administration',
    permission: Permissions.clinicSettingsEdit,
  ),
];

bool _isFeatureLocked(WidgetRef ref, _ClinicService service) {
  final feature = service.feature;
  final session = ref.watch(userSessionProvider).valueOrNull;
  return feature != null &&
      session != null &&
      !FeatureGateService.canAccess(
        subscriptionPlan: session.clinic.subscriptionPlan,
        feature: feature,
      );
}

String _vaccineStatus(Vaccination vaccination) {
  final due = vaccination.nextDueDate;
  if (vaccination.status.toLowerCase() == 'cancelled') return 'Cancelled';
  if (due == null) return 'Completed';
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  if (due.isBefore(start)) return 'Overdue';
  if (due.isBefore(start.add(const Duration(days: 1)))) return 'Due Today';
  return 'Upcoming';
}

class _VaccineStatusBadge extends StatelessWidget {
  const _VaccineStatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = status == 'Overdue'
        ? Theme.of(context).colorScheme.error
        : status == 'Due Today'
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PatientAvatar extends StatelessWidget {
  const _PatientAvatar({required this.name, required this.photo});
  final String name;
  final String? photo;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: 52,
      height: 52,
      child: photo != null && photo!.isNotEmpty
          ? Image.file(
              File(photo!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(context),
            )
          : _fallback(context),
    ),
  );
  Widget _fallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Center(
      child: Text(
        name.substring(0, 1).toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

class _OperationsEmpty extends StatelessWidget {
  const _OperationsEmpty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _OperationsDenied extends StatelessWidget {
  const _OperationsDenied();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'You do not have permission to view this clinic operation.',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
