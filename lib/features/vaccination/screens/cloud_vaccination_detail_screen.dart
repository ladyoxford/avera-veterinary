import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/models/vaccine_catalogue.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/security/access_control.dart';
import '../../../core/services/animal_age_service.dart';
import '../../shared/widgets/avera_ui.dart';

class CloudVaccinationDetailScreen extends ConsumerStatefulWidget {
  const CloudVaccinationDetailScreen({super.key, required this.vaccinationId});
  final String vaccinationId;

  @override
  ConsumerState<CloudVaccinationDetailScreen> createState() =>
      _CloudVaccinationDetailScreenState();
}

class _CloudVaccinationDetailScreenState
    extends ConsumerState<CloudVaccinationDetailScreen> {
  late Future<Map<String, dynamic>> _detail;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _detail = ref
      .read(clinicalRemoteDataSourceProvider)
      .vaccination(widget.vaccinationId);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vaccination')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: OutlinedButton.icon(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry vaccination'),
            ),
          );
        }
        return _VaccinationBody(
          payload: snapshot.data!,
          onDoseRecorded: () => setState(_reload),
        );
      },
    ),
  );
}

class _VaccinationBody extends ConsumerWidget {
  const _VaccinationBody({required this.payload, required this.onDoseRecorded});
  final Map<String, dynamic> payload;
  final VoidCallback onDoseRecorded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = Map<String, dynamic>.from(payload['vaccination'] as Map);
    final history = (payload['history'] as List<dynamic>? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final patientId = '${record['patient_id']}';
    final vaccineName = '${record['vaccine_name']}';
    final administeredAt = DateTime.tryParse(
      '${record['administered_at']}',
    )?.toLocal();
    final dueAt = DateTime.tryParse('${record['next_due_at']}')?.toLocal();
    final birthDate = DateTime.tryParse('${record['date_of_birth']}');
    final protocol = VaccineCatalogue.protocols
        .where((item) => item.name == vaccineName)
        .firstOrNull;
    final session = ref.watch(userSessionProvider).valueOrNull;
    final format = DateFormat.yMMMd();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
      children: [
        AveraPageHeader(
          title: vaccineName,
          subtitle: '${record['patient_name']} - ${record['hospital_number']}',
        ),
        const SizedBox(height: 24),
        AveraLabeledFieldCard(
          label: 'Patient',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${record['patient_name']}',
                style: averaText(context).fieldValue,
              ),
              Text(
                '${record['species']}${record['breed'] == null ? '' : ' - ${record['breed']}'}',
                style: averaText(context).caption,
              ),
              if (birthDate != null && administeredAt != null)
                Text(
                  'Age at vaccination: ${AnimalAgeService.displayAge(birthDate: birthDate, referenceDate: administeredAt, estimated: record['is_date_of_birth_estimated'] == true)}',
                  style: averaText(context).caption,
                ),
              Text(
                'Owner: ${record['owner_name'] ?? 'Not recorded'}',
                style: averaText(context).caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AveraLabeledFieldCard(
          label: 'Schedule',
          child: Text(
            'Last given: ${administeredAt == null ? 'Not recorded' : format.format(administeredAt)}\nDue: ${dueAt == null ? 'Not scheduled' : format.format(dueAt)}\nStatus: ${record['status'] ?? 'Completed'}',
            style: averaText(context).fieldValue,
          ),
        ),
        if (protocol != null) ...[
          const SizedBox(height: 16),
          AveraLabeledFieldCard(
            label: 'Protocol Guidance',
            child: Text(
              protocol.education,
              style: averaText(context).fieldValue,
            ),
          ),
        ],
        const SizedBox(height: 16),
        AveraLabeledFieldCard(
          label: 'Administration',
          child: Text(
            'Batch: ${record['batch_number'] ?? 'Not recorded'}\nManufacturer: ${record['manufacturer'] ?? 'Not recorded'}\nRoute: ${record['route'] ?? 'Not recorded'}\nDose: ${record['dose'] ?? 'Not recorded'}\nClinician: ${record['administered_by_name'] ?? 'Not recorded'}',
            style: averaText(context).fieldValue,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              context.push('/animals/${Uri.encodeComponent(patientId)}'),
          icon: const Icon(Icons.pets_rounded),
          label: const Text('Open Patient File'),
        ),
        if (session?.can(Permissions.vaccinationsAdd) == true) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await context.push(
                '/vaccinations/record?remotePatientId=${Uri.encodeQueryComponent(patientId)}&remoteVaccinationId=${Uri.encodeQueryComponent(widgetId(record))}&vaccineName=${Uri.encodeQueryComponent(vaccineName)}',
              );
              onDoseRecorded();
            },
            icon: const Icon(Icons.vaccines_rounded),
            label: const Text('Record Dose'),
          ),
        ],
        const SizedBox(height: 28),
        const AveraSectionHeader(title: 'Vaccination History'),
        const SizedBox(height: 12),
        if (history.isEmpty)
          const AveraSurfaceCard(child: Text('No previous doses recorded.'))
        else
          AveraSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < history.length; index++) ...[
                  ListTile(
                    title: Text('${history[index]['vaccine_name']}'),
                    subtitle: Text(_historyText(history[index])),
                  ),
                  if (index != history.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

String widgetId(Map<String, dynamic> value) => '${value['vaccination_id']}';

String _historyText(Map<String, dynamic> value) {
  final date = DateTime.tryParse('${value['administered_at']}')?.toLocal();
  return '${date == null ? 'Date unavailable' : DateFormat.yMMMd().format(date)} | Batch: ${value['batch_number'] ?? 'Not recorded'} | ${value['manufacturer'] ?? 'Manufacturer not recorded'} | ${value['route'] ?? 'Route not recorded'} | ${value['administered_by_name'] ?? 'Clinician not recorded'}';
}
