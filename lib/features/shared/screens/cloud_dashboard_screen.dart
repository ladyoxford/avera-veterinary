import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/remote/cloud_clinical_state.dart';

class CloudDashboardScreen extends ConsumerWidget {
  const CloudDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(remoteDashboardProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/animals/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Register patient'),
      ),
      body: SafeArea(
        child: dashboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: FilledButton.icon(
              onPressed: () => ref.invalidate(remoteDashboardProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry dashboard'),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(remoteDashboardProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Text(
                  'Clinic Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Live clinic summary',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 700 ? 4 : 2;
                    final cards = [
                      (
                        'Registered Pets',
                        data.registeredPatients,
                        Icons.pets_rounded,
                        '/animals',
                      ),
                      (
                        'Today\'s Schedule',
                        data.todaysSchedule,
                        Icons.calendar_month_rounded,
                        '/appointments',
                      ),
                      (
                        'Vaccines Due',
                        data.vaccinationsDue,
                        Icons.vaccines_rounded,
                        '/vaccinations',
                      ),
                      (
                        'Low Stock',
                        data.lowStock,
                        Icons.inventory_2_outlined,
                        '/inventory',
                      ),
                      (
                        'Active Admissions',
                        data.activeHospitalizations,
                        Icons.local_hospital_outlined,
                        '/operations/hospitalization',
                      ),
                      (
                        'Laboratory Pending',
                        data.pendingLaboratoryReports,
                        Icons.science_outlined,
                        '/operations/laboratory',
                      ),
                    ];
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cards.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final card = cards[index];
                        return Card(
                          child: InkWell(
                            onTap: () => context.push(card.$4),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Icon(card.$3),
                                  Text(
                                    '${card.$2}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  Text(card.$1),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  'Recent Activity',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: data.recentActivity
                        .take(8)
                        .map(
                          (entry) => ListTile(
                            leading: const Icon(Icons.history_rounded),
                            title: Text(
                              entry['summary'] as String? ??
                                  'Clinical activity',
                            ),
                            subtitle: Text(
                              entry['type'] as String? ?? 'Record',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openActivity(context, entry),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openActivity(BuildContext context, Map<String, dynamic> entry) {
    final type = entry['type']?.toString();
    final recordId = entry['record_id']?.toString();
    final patientId = entry['patient_id']?.toString();
    if (type == 'Consultation' && recordId != null && patientId != null) {
      context.push(
        '/consultations/$recordId?patientId=${Uri.encodeQueryComponent(patientId)}',
      );
      return;
    }
    if (type == 'Schedule' && recordId != null) {
      context.push('/appointments/$recordId');
      return;
    }
    if (type == 'Schedule') context.push('/appointments');
  }
}
