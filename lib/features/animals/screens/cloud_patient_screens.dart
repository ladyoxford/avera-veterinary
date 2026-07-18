import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/remote/clinical_remote_data_source.dart';

class CloudPatientListScreen extends ConsumerStatefulWidget {
  const CloudPatientListScreen({super.key});

  @override
  ConsumerState<CloudPatientListScreen> createState() => _CloudPatientListScreenState();
}

class _CloudPatientListScreenState extends ConsumerState<CloudPatientListScreen> {
  final _scrollController = ScrollController();
  Timer? _debounce;
  String _filter = 'Active';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.extentAfter < 360) {
        ref.read(remotePatientListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() { _debounce?.cancel(); _scrollController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remotePatientListProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Register patient', icon: const Icon(Icons.add_rounded), label: const Text('Register pet'), onPressed: () => context.push('/animals/new'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(remotePatientListProvider.notifier).refresh(status: _filter),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Registered Pets', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Live clinic records', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  SearchBar(
                    leading: const Icon(Icons.search_rounded), hintText: 'Search name, hospital number, owner or phone',
                    onChanged: (value) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(remotePatientListProvider.notifier).refresh(search: value, status: _filter)); },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: ['Active', 'All Animals', 'Deceased', 'Relocated'].map((item) => Padding(
                    padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(item), selected: item == _filter, onSelected: (_) { setState(() => _filter = item); ref.read(remotePatientListProvider.notifier).refresh(status: item); }),
                  )).toList())),
                ])),
              ),
              if (state.isLoading && state.items.isEmpty) const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              if (!state.isLoading && state.items.isEmpty) SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(state.error == null ? 'No patients found.' : 'Unable to load patient records.'))),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverList.separated(
                  itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => index >= state.items.length
                      ? const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
                      : _CloudPatientCard(patient: state.items[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloudPatientCard extends StatelessWidget {
  const _CloudPatientCard({required this.patient});
  final RemotePatient patient;
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/animals/${patient.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(radius: 28, child: Text(patient.name.isEmpty ? '?' : patient.name[0].toUpperCase())),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(patient.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3), Text(patient.hospitalNumber, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6), Text([patient.species, patient.breed, patient.sex].whereType<String>().where((item) => item.isNotEmpty).join(' | '), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3), Text('${patient.ownerName} | ${patient.ownerPhone}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ])),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      );
}

class CloudPatientMedicalFileScreen extends ConsumerWidget {
  const CloudPatientMedicalFileScreen({super.key, required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(remotePatientMedicalFileProvider(patientId));
    return Scaffold(
      appBar: AppBar(title: const Text('Medical File')),
      body: file.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Unable to open this patient medical file.')),
        data: (value) => ListView(padding: const EdgeInsets.all(20), children: [
          Text(value.patient.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('${value.patient.hospitalNumber} | ${value.patient.species}${value.patient.breed == null ? '' : ' | ${value.patient.breed}'}'),
          const SizedBox(height: 24),
          for (final item in _sections) _CloudMedicalSection(patientId: patientId, label: item.$1, route: item.$2, summary: value.summaries[item.$3] ?? const {}),
          const SizedBox(height: 20), Text('Timeline', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (value.timeline.isEmpty) const Text('No recent clinical activity.'),
          for (final event in value.timeline) ListTile(leading: const Icon(Icons.history_rounded), title: Text(event['summary'] as String? ?? 'Clinical record'), subtitle: Text(event['type'] as String? ?? 'Record')),
        ]),
      ),
    );
  }
}

const _sections = [
  ('Consultations', 'consultations', 'consultations'), ('Vaccinations', 'vaccinations', 'vaccinations'), ('Laboratory', 'laboratory', 'laboratory'),
  ('Hospitalization', 'hospitalizations', 'hospitalizations'), ('Surgery', 'surgeries', 'surgeries'), ('Prescriptions', 'prescriptions', 'prescriptions'),
];

class _CloudMedicalSection extends ConsumerStatefulWidget {
  const _CloudMedicalSection({required this.patientId, required this.label, required this.route, required this.summary});
  final String patientId;
  final String label;
  final String route;
  final Map<String, dynamic> summary;
  @override
  ConsumerState<_CloudMedicalSection> createState() => _CloudMedicalSectionState();
}

class _CloudMedicalSectionState extends ConsumerState<_CloudMedicalSection> {
  Future<RemotePage<Map<String, dynamic>>>? _records;
  @override
  Widget build(BuildContext context) => Card(child: ExpansionTile(
        title: Text(widget.label), subtitle: Text('${widget.summary['count'] ?? 0} records'),
        onExpansionChanged: (open) { if (open && _records == null) setState(() => _records = ref.read(clinicalRemoteDataSourceProvider).patientSection(widget.patientId, widget.route)); },
        children: [if (_records != null) FutureBuilder<RemotePage<Map<String, dynamic>>>(future: _records, builder: (context, snapshot) {
          if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          if (snapshot.data!.items.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No records.'));
          return Column(children: snapshot.data!.items.take(5).map((record) => ListTile(title: Text(_recordTitle(record)), subtitle: Text(_recordDate(record) ?? ''))).toList());
        })],
      ));
  String _recordTitle(Map<String, dynamic> item) => (item['final_diagnosis'] ?? item['vaccine_name'] ?? item['test_type'] ?? item['diagnosis'] ?? item['procedure_name'] ?? item['drug_name'] ?? 'Clinical record') as String;
  String? _recordDate(Map<String, dynamic> item) => (item['occurred_at'] ?? item['administered_at'] ?? item['requested_at'] ?? item['admitted_at'] ?? item['performed_at'] ?? item['prescribed_at']) as String?;
}
