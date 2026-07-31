import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/services/animal_age_service.dart';
import '../../../core/theme/app_theme.dart';

class AnimalProfileScreen extends ConsumerWidget {
  const AnimalProfileScreen({
    super.key,
    required this.animalId,
    this.initialTab = 0,
  });

  final int animalId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(animalProfileProvider(animalId));
    final session = ref.watch(userSessionProvider).valueOrNull;
    final index = initialTab.clamp(0, _recordTitles.length - 1);
    final title = _recordTitles[index];
    final action = _medicalFileActions[index];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            profile.maybeWhen(
              data: (data) => Text(
                'Medical File • ${data.animal.animalName} • ${data.animal.hospitalNumber}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      body: profile.when(
        loading: () => const _ProfileSkeleton(),
        error: (error, _) => _ModuleEmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Unable to open medical file',
          message: error.toString(),
        ),
        data: (data) => _recordContent(
          index: index,
          profile: data,
          clinicName: session?.clinic.clinicName,
        ),
      ),
      floatingActionButton:
          action == null || session?.can(action.permission) != true
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push(
                action.route == '/consultations/new'
                    ? '${action.route}?animalId=$animalId'
                    : action.route,
              ),
              icon: Icon(action.icon),
              label: Text(action.label),
            ),
    );
  }
}

Widget _recordContent({
  required int index,
  required AnimalProfile profile,
  String? clinicName,
}) {
  switch (index) {
    case 0:
      return _OverviewTab(profile: profile, clinicName: clinicName);
    case 1:
      return _SignalmentTab(profile: profile);
    case 2:
      return _OwnerTab(profile: profile);
    case 3:
      return _MedicalHistoryTab(profile: profile);
    case 4:
      return _ConsultationsTab(profile: profile);
    case 5:
      return _VaccinationsTab(profile: profile);
    case 6:
      return const _EmptyModule(
        title: 'Laboratory',
        icon: Icons.science_outlined,
      );
    case 7:
      return const _EmptyModule(
        title: 'Hospitalization',
        icon: Icons.local_hospital_outlined,
      );
    case 8:
      return const _EmptyModule(
        title: 'Surgery',
        icon: Icons.medical_services_outlined,
      );
    case 9:
      return _MedicationsTab(profile: profile);
    case 10:
      return _BillingTab(profile: profile);
    case 11:
      return _AppointmentsTab(profile: profile);
    case 12:
      return const _EmptyModule(
        title: 'Documents',
        icon: Icons.description_outlined,
      );
    case 13:
      return const _EmptyModule(
        title: 'Images',
        icon: Icons.photo_library_outlined,
      );
    case 14:
      return _TimelineTab(profile: profile);
    default:
      return const SizedBox.shrink();
  }
}

const _recordTitles = <String>[
  'Medical File',
  'Signalment',
  'Owner',
  'Medical History',
  'Consultations',
  'Vaccinations',
  'Laboratory',
  'Hospitalization',
  'Surgery',
  'Medications',
  'Billing',
  'Schedule',
  'Documents',
  'Images & AI Recognition',
  'Timeline',
];

class _MedicalFileAction {
  const _MedicalFileAction({
    required this.label,
    required this.icon,
    required this.route,
    required this.permission,
  });

  final String label;
  final IconData icon;
  final String route;
  final String permission;
}

const _medicalFileActions = <int, _MedicalFileAction>{
  3: _MedicalFileAction(
    label: 'New Consultation',
    icon: Icons.add_rounded,
    route: '/consultations/new',
    permission: 'Create Consultation',
  ),
  4: _MedicalFileAction(
    label: 'New Consultation',
    icon: Icons.add_rounded,
    route: '/consultations/new',
    permission: 'Create Consultation',
  ),
  5: _MedicalFileAction(
    label: 'Add Vaccine',
    icon: Icons.vaccines_outlined,
    route: '/vaccinations',
    permission: 'Manage Vaccinations',
  ),
  9: _MedicalFileAction(
    label: 'New Consultation',
    icon: Icons.add_rounded,
    route: '/consultations/new',
    permission: 'Create Consultation',
  ),
  10: _MedicalFileAction(
    label: 'Add Invoice',
    icon: Icons.receipt_long_outlined,
    route: '/billing',
    permission: 'Manage Billing',
  ),
  11: _MedicalFileAction(
    label: 'Add Schedule Entry',
    icon: Icons.calendar_month_outlined,
    route: '/appointments',
    permission: 'Manage Appointments',
  ),
};

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.profile, this.clinicName});
  final AnimalProfile profile;
  final String? clinicName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referenceDate = ref.watch(animalAgeReferenceDateProvider);
    return _TabCanvas(
      children: [
        _SectionLabel('Patient details'),
        _PatientDetailsCard(
          profile: profile,
          clinicName: clinicName,
          referenceDate: referenceDate,
          onPhotoPressed: () => _changePhoto(context, ref),
        ),
        const SizedBox(height: 24),
        _SectionLabel('Owner details'),
        _OwnerDetailsCard(profile: profile),
      ],
    );
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final animal = profile.animal;
    final source = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Wrap(
            children: [
              const ListTile(
                title: Text('Change Patient Photo'),
                subtitle: Text('Choose a source for this patient image.'),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
              ),
              if (animal.photo != null && animal.photo!.isNotEmpty)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: const Text('Remove Photo'),
                  onTap: () => Navigator.pop(sheetContext, _PhotoAction.remove),
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    try {
      String? path;
      if (source != _PhotoAction.remove) {
        final image = await ImagePicker().pickImage(
          source: source == _PhotoAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 88,
        );
        if (image == null) return;
        path = await ref
            .read(clinicRepositoryProvider)
            .cacheAnimalPhoto(image.path);
      }
      await ref
          .read(clinicRepositoryProvider)
          .updateAnimalPhoto(
            animalId: animal.id,
            photoPath: path,
            session: session,
          );
      ref.invalidate(animalProfileProvider(animal.id));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

enum _PhotoAction { camera, gallery, remove }

class _PatientDetailsCard extends StatelessWidget {
  const _PatientDetailsCard({
    required this.profile,
    required this.referenceDate,
    this.clinicName,
    this.onPhotoPressed,
  });
  final AnimalProfile profile;
  final DateTime referenceDate;
  final String? clinicName;
  final VoidCallback? onPhotoPressed;

  @override
  Widget build(BuildContext context) {
    final animal = profile.animal;
    final theme = Theme.of(context);
    final lastVisit = profile.visits.isEmpty
        ? null
        : profile.visits.reduce(
            (current, visit) =>
                visit.visitDate.isAfter(current.visitDate) ? visit : current,
          );
    final nextAppointment = profile.appointments
        .where(
          (appointment) => appointment.appointmentDate.isAfter(DateTime.now()),
        )
        .fold<DateTime?>(
          null,
          (current, appointment) =>
              current == null || appointment.appointmentDate.isBefore(current)
              ? appointment.appointmentDate
              : current,
        );
    return _EmrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PatientPhoto(
                name: animal.animalName,
                photo: animal.photo,
                onPressed: onPhotoPressed,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animal.animalName,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _signalment(
                        animal.species,
                        animal.breed,
                        animal.sex,
                        _currentAge(animal, referenceDate, compact: true),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StatusBadge(status: animal.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _InformationGrid(
            items: [
              _InfoItem(
                Icons.badge_outlined,
                'Hospital number',
                animal.hospitalNumber,
              ),
              _InfoItem(Icons.pets_outlined, 'Species', animal.species),
              _InfoItem(
                Icons.category_outlined,
                'Breed',
                animal.breed ?? 'Not recorded',
              ),
              _InfoItem(Icons.wc_rounded, 'Sex', animal.sex ?? 'Not recorded'),
              _InfoItem(
                Icons.cake_outlined,
                'Current age',
                _currentAge(animal, referenceDate),
              ),
              _InfoItem(
                Icons.event_outlined,
                'Date of birth',
                _birthDate(animal),
              ),
              _InfoItem(
                Icons.monitor_weight_outlined,
                'Weight',
                animal.weight == null
                    ? 'Not recorded'
                    : '${animal.weight!.toStringAsFixed(1)} kg',
              ),
              _InfoItem(
                Icons.palette_outlined,
                'Color',
                animal.color ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.qr_code_rounded,
                'Microchip',
                animal.microchipNumber ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.calendar_today_outlined,
                'Registered',
                _date(animal.dateRegistered),
              ),
              _InfoItem(
                Icons.business_outlined,
                'Clinic',
                clinicName ?? 'Current clinic',
              ),
              _InfoItem(
                Icons.person_outline_rounded,
                'Owner',
                profile.owner.fullName,
              ),
              _InfoItem(
                Icons.history_rounded,
                'Last visit',
                lastVisit == null
                    ? 'No visits recorded'
                    : _date(lastVisit.visitDate),
              ),
              _InfoItem(
                Icons.event_available_outlined,
                'Next scheduled visit',
                nextAppointment == null
                    ? 'None scheduled'
                    : _date(nextAppointment),
              ),
            ],
          ),
          if (animal.notes != null && animal.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionLabel('Quick summary'),
            const SizedBox(height: 8),
            Text(animal.notes!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _SignalmentTab extends ConsumerWidget {
  const _SignalmentTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = profile.animal;
    final referenceDate = ref.watch(animalAgeReferenceDateProvider);
    return _TabCanvas(
      children: [
        _SectionLabel('Signalment'),
        _EmrCard(
          child: _InformationGrid(
            items: [
              _InfoItem(Icons.pets_outlined, 'Species', a.species),
              _InfoItem(
                Icons.category_outlined,
                'Breed',
                a.breed ?? 'Not recorded',
              ),
              _InfoItem(Icons.wc_rounded, 'Sex', a.sex ?? 'Not recorded'),
              _InfoItem(
                Icons.cake_outlined,
                'Current age',
                _currentAge(a, referenceDate),
              ),
              _InfoItem(Icons.event_outlined, 'Date of birth', _birthDate(a)),
              _InfoItem(
                Icons.monitor_weight_outlined,
                'Weight',
                a.weight == null
                    ? 'Not recorded'
                    : '${a.weight!.toStringAsFixed(1)} kg',
              ),
              _InfoItem(
                Icons.palette_outlined,
                'Color',
                a.color ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.qr_code_rounded,
                'Microchip',
                a.microchipNumber ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.calendar_today_outlined,
                'Registration date',
                _date(a.dateRegistered),
              ),
              _InfoItem(Icons.verified_outlined, 'Status', a.status),
            ],
          ),
        ),
      ],
    );
  }
}

class _OwnerTab extends StatelessWidget {
  const _OwnerTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Owner details'),
      _OwnerDetailsCard(profile: profile),
    ],
  );
}

class _OwnerDetailsCard extends StatelessWidget {
  const _OwnerDetailsCard({required this.profile});
  final AnimalProfile profile;

  @override
  Widget build(BuildContext context) {
    final owner = profile.owner;
    final address = [
      owner.address,
      owner.city,
      owner.state,
      owner.country,
    ].where((value) => value != null && value.trim().isNotEmpty).join(', ');
    return _EmrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OwnerAvatar(name: owner.fullName),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owner.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Primary owner',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.phone_outlined,
            label: 'Phone number',
            value: owner.phone,
          ),
          _InfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: owner.email ?? 'Not recorded',
          ),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: address.isEmpty ? 'Not recorded' : address,
          ),
          _InfoRow(
            icon: Icons.work_outline_rounded,
            label: 'Occupation',
            value: owner.occupation ?? 'Not recorded',
            last: true,
          ),
        ],
      ),
    );
  }
}

class _MedicalHistoryTab extends StatelessWidget {
  const _MedicalHistoryTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Medical history'),
      if (profile.visits.isEmpty)
        const _ModuleEmptyState(
          icon: Icons.history_toggle_off_outlined,
          title: 'No medical history yet',
          message: 'Consultations will appear here as they are recorded.',
        )
      else
        for (final visit in profile.visits) ...[
          _ConsultationRow(
            visit: visit,
            dateOfBirth: profile.animal.dateOfBirth,
            isEstimated: profile.animal.isDateOfBirthEstimated,
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

class _ConsultationsTab extends StatelessWidget {
  const _ConsultationsTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Consultation history'),
      if (profile.visits.isEmpty)
        const _ModuleEmptyState(
          icon: Icons.medical_information_outlined,
          title: 'No consultations yet',
          message: 'New consultation records will be listed here.',
        )
      else
        for (final visit in profile.visits) ...[
          _ConsultationRow(
            visit: visit,
            dateOfBirth: profile.animal.dateOfBirth,
            isEstimated: profile.animal.isDateOfBirthEstimated,
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

class _ConsultationRow extends StatelessWidget {
  const _ConsultationRow({
    required this.visit,
    required this.dateOfBirth,
    required this.isEstimated,
  });

  final dynamic visit;
  final DateTime? dateOfBirth;
  final bool isEstimated;

  @override
  Widget build(BuildContext context) {
    final title = visit.diagnosis ?? visit.chiefComplaint ?? 'Consultation';
    final summary =
        visit.chiefComplaint ?? visit.history ?? 'No summary recorded';
    return _EmrCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/consultations/${visit.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateMarker(date: visit.visitDate),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${_date(visit.visitDate)} - ${visit.veterinarian ?? 'Veterinarian not recorded'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (dateOfBirth != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Age at consultation: '
                        '${AnimalAgeService.displayAge(birthDate: dateOfBirth!, referenceDate: visit.visitDate, estimated: isEstimated)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(status: visit.status),
                  const SizedBox(height: 12),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Retained only for compatibility with pre-existing detail layouts.
// ignore: unused_element
class _VisitRecordCard extends StatelessWidget {
  const _VisitRecordCard({required this.visit});
  final dynamic visit;

  @override
  Widget build(BuildContext context) {
    final title = visit.chiefComplaint ?? visit.diagnosis ?? 'Consultation';
    return _EmrCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: _DateMarker(date: visit.visitDate),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_date(visit.visitDate)}  •  ${visit.veterinarian ?? 'Veterinarian not recorded'}',
          ),
        ),
        trailing: _StatusBadge(status: visit.status),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          _InformationGrid(
            items: [
              _InfoItem(
                Icons.chat_bubble_outline_rounded,
                'Chief complaint',
                visit.chiefComplaint ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.history_rounded,
                'History',
                visit.history ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.medical_services_outlined,
                'Physical examination',
                visit.physicalExamination ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.thermostat_outlined,
                'Temperature',
                visit.temperature == null
                    ? 'Not recorded'
                    : '${visit.temperature} °C',
              ),
              _InfoItem(
                Icons.favorite_outline_rounded,
                'Pulse',
                visit.pulse == null ? 'Not recorded' : '${visit.pulse} bpm',
              ),
              _InfoItem(
                Icons.air_rounded,
                'Respiration',
                visit.respiration == null
                    ? 'Not recorded'
                    : '${visit.respiration} rpm',
              ),
              _InfoItem(
                Icons.medical_information_outlined,
                'Diagnosis',
                visit.diagnosis ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.account_tree_outlined,
                'Differentials',
                visit.differentialDiagnosis ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.medication_outlined,
                'Treatment',
                visit.treatment ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.receipt_long_outlined,
                'Prescription',
                visit.prescription ?? 'Not recorded',
              ),
              _InfoItem(
                Icons.event_available_outlined,
                'Follow-up',
                visit.nextAppointment == null
                    ? 'Not recorded'
                    : _date(visit.nextAppointment),
              ),
              _InfoItem(
                Icons.person_outline_rounded,
                'Veterinarian',
                visit.veterinarian ?? 'Not recorded',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaccinationsTab extends StatelessWidget {
  const _VaccinationsTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Vaccination records'),
      if (profile.vaccinations.isEmpty)
        const _ModuleEmptyState(
          icon: Icons.vaccines_outlined,
          title: 'No vaccinations yet',
          message: 'Vaccination records and certificates will appear here.',
        )
      else
        for (final vaccine in profile.vaccinations) ...[
          _VaccineCard(vaccine: vaccine),
          const SizedBox(height: 12),
        ],
    ],
  );
}

class _VaccineCard extends StatelessWidget {
  const _VaccineCard({required this.vaccine});
  final dynamic vaccine;
  @override
  Widget build(BuildContext context) => _EmrCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.vaccines_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vaccine.vaccine,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _StatusBadge(status: vaccine.status),
          ],
        ),
        const SizedBox(height: 16),
        _InformationGrid(
          items: [
            _InfoItem(
              Icons.business_outlined,
              'Manufacturer',
              vaccine.manufacturer ?? 'Not recorded',
            ),
            _InfoItem(
              Icons.numbers_rounded,
              'Batch number',
              vaccine.batchNumber ?? 'Not recorded',
            ),
            _InfoItem(
              Icons.medication_outlined,
              'Dose',
              vaccine.dose ?? 'Not recorded',
            ),
            _InfoItem(
              Icons.route_outlined,
              'Route',
              vaccine.route ?? 'Not recorded',
            ),
            _InfoItem(
              Icons.calendar_today_outlined,
              'Date given',
              _date(vaccine.dateGiven),
            ),
            _InfoItem(
              Icons.event_repeat_outlined,
              'Next due',
              vaccine.nextDueDate == null
                  ? 'Not recorded'
                  : _date(vaccine.nextDueDate),
            ),
            _InfoItem(
              Icons.person_outline_rounded,
              'Veterinarian',
              vaccine.veterinarian ?? vaccine.administeredBy ?? 'Not recorded',
            ),
            _InfoItem(
              Icons.verified_outlined,
              'Certificate',
              vaccine.certificateNumber ?? 'Not issued',
            ),
          ],
        ),
      ],
    ),
  );
}

class _MedicationsTab extends StatelessWidget {
  const _MedicationsTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) {
    final prescribed = profile.visits
        .where(
          (visit) =>
              visit.prescription != null &&
              visit.prescription!.trim().isNotEmpty,
        )
        .toList();
    return _TabCanvas(
      children: [
        _SectionLabel('Medications'),
        if (prescribed.isEmpty)
          const _ModuleEmptyState(
            icon: Icons.medication_outlined,
            title: 'No medications prescribed',
            message: 'Prescriptions from consultations will be collected here.',
          )
        else
          for (final visit in prescribed) ...[
            _EmrCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.medication_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visit.prescription!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Prescribed ${_date(visit.visitDate)}  •  ${visit.veterinarian ?? 'Veterinarian not recorded'}',
                        ),
                        if (visit.treatment != null) ...[
                          const SizedBox(height: 6),
                          Text(visit.treatment!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _BillingTab extends StatelessWidget {
  const _BillingTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Billing information'),
      if (profile.sales.isEmpty)
        const _ModuleEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No billing records yet',
          message:
              'Invoices and sales linked to this medical file will appear here.',
        )
      else
        for (final sale in profile.sales) ...[
          _EmrCard(
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sale #${sale.id}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_date(sale.date)}  •  ${sale.quantity} item${sale.quantity == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      (sale.quantity * sale.price).toStringAsFixed(2),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const _StatusBadge(status: 'Completed'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

class _AppointmentsTab extends StatelessWidget {
  const _AppointmentsTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel('Schedule'),
      if (profile.appointments.isEmpty)
        const _ModuleEmptyState(
          icon: Icons.event_available_outlined,
          title: 'No appointments scheduled',
          message: 'Future and past appointments will appear here.',
        )
      else
        for (final appointment in profile.appointments) ...[
          _EmrCard(
            child: Row(
              children: [
                _DateMarker(date: appointment.appointmentDate),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.purpose,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(_dateTime(appointment.appointmentDate)),
                    ],
                  ),
                ),
                _StatusBadge(status: appointment.status),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
    ],
  );
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.profile});
  final AnimalProfile profile;
  @override
  Widget build(BuildContext context) {
    final events = <_TimelineEvent>[
      ...profile.visits.map(
        (v) => _TimelineEvent(
          date: v.visitDate,
          icon: Icons.medical_information_outlined,
          title: v.diagnosis ?? v.chiefComplaint ?? 'Consultation',
          description: v.treatment ?? v.history ?? 'Consultation recorded',
        ),
      ),
      ...profile.vaccinations.map(
        (v) => _TimelineEvent(
          date: v.dateGiven,
          icon: Icons.vaccines_outlined,
          title: v.vaccine,
          description:
              'Vaccination administered${v.nextDueDate == null ? '' : '; next due ${_date(v.nextDueDate!)}'}',
        ),
      ),
      ...profile.appointments.map(
        (a) => _TimelineEvent(
          date: a.appointmentDate,
          icon: Icons.event_outlined,
          title: a.purpose,
          description: 'Schedule ${a.status.toLowerCase()}',
        ),
      ),
      ...profile.sales.map(
        (s) => _TimelineEvent(
          date: s.date,
          icon: Icons.receipt_long_outlined,
          title: 'Sale #${s.id}',
          description: '${s.quantity} item${s.quantity == 1 ? '' : 's'} billed',
        ),
      ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return _TabCanvas(
      children: [
        _SectionLabel('Timeline'),
        if (events.isEmpty)
          const _ModuleEmptyState(
            icon: Icons.timeline_outlined,
            title: 'No timeline events yet',
            message:
                'Clinical activity will be collected here in chronological order.',
          )
        else
          for (var index = 0; index < events.length; index++)
            _TimelineEventCard(
              event: events[index],
              isLast: index == events.length - 1,
            ),
      ],
    );
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.date,
    required this.icon,
    required this.title,
    required this.description,
  });
  final DateTime date;
  final IconData icon;
  final String title;
  final String description;
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({required this.event, required this.isLast});
  final _TimelineEvent event;
  final bool isLast;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  event.icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EmrCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dateTime(event.date),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(event.description),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyModule extends StatelessWidget {
  const _EmptyModule({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _TabCanvas(
    children: [
      _SectionLabel(title),
      _ModuleEmptyState(
        icon: icon,
        title: 'No $title records yet',
        message:
            'This clinical section is ready to display records when they are added.',
      ),
    ],
  );
}

class _TabCanvas extends StatelessWidget {
  const _TabCanvas({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _EmrCard extends StatelessWidget {
  const _EmrCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .6),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _InformationGrid extends StatelessWidget {
  const _InformationGrid({required this.items});
  final List<_InfoItem> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 700
          ? 3
          : constraints.maxWidth >= 430
          ? 2
          : 1;
      final width = (constraints.maxWidth - ((columns - 1) * 16)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 18,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: _InfoCell(item: item),
            ),
        ],
      );
    },
  );
}

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.item});
  final _InfoItem item;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(item.icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(item.value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool last;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _InfoCell(item: _InfoItem(icon, label, value)),
      ),
      if (!last) const Divider(height: 1),
    ],
  );
}

class _DateMarker extends StatelessWidget {
  const _DateMarker({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          DateFormat.MMM().format(date).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        Text(
          '${date.day}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final normalized = status.toLowerCase();
    final color =
        normalized.contains('deceased') ||
            normalized.contains('cancel') ||
            normalized.contains('overdue')
        ? semantic.danger
        : normalized.contains('pending') ||
              normalized.contains('relocat') ||
              normalized.contains('scheduled')
        ? semantic.warning
        : semantic.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _PatientPhoto extends StatelessWidget {
  const _PatientPhoto({
    required this.name,
    required this.photo,
    this.onPressed,
  });

  final String name;
  final String? photo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 116,
      height: 116,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Semantics(
              button: onPressed != null,
              label: 'Change $name patient photo',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: _AnimalAvatar(name: name, photo: photo, size: 116),
                ),
              ),
            ),
          ),
          if (onPressed != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: scheme.primary,
                elevation: 3,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Change patient photo',
                  onPressed: onPressed,
                  icon: Icon(Icons.camera_alt_rounded, color: scheme.onPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimalAvatar extends StatelessWidget {
  const _AnimalAvatar({
    required this.name,
    required this.photo,
    required this.size,
  });
  final String name;
  final String? photo;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = _InitialAvatar(
      name: name,
      size: size,
      color: _avatarColors[name.hashCode.abs() % _avatarColors.length],
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: photo == null || photo!.isEmpty
            ? fallback
            : Image.file(
                File(photo!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
      ),
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  const _OwnerAvatar({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: _InitialAvatar(
      name: name,
      size: 52,
      color: _avatarColors[name.hashCode.abs() % _avatarColors.length],
    ),
  );
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.name,
    required this.size,
    required this.color,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: ColoredBox(
      color: color,
      child: Center(
        child: Text(
          _initials(name),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.white),
        ),
      ),
    ),
  );
}

class _ModuleEmptyState extends StatelessWidget {
  const _ModuleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => _EmrCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      _SkeletonBlock(height: 260),
      SizedBox(height: 24),
      _SkeletonBlock(height: 220),
    ],
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) =>
      Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(20),
            ),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .shimmer(duration: 1200.ms);
}

String _date(DateTime value) => DateFormat.yMMMd().format(value);
String _dateTime(DateTime value) => DateFormat.yMMMd().add_jm().format(value);
String _initials(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part[0])
    .join()
    .toUpperCase();
String _currentAge(
  Animal animal,
  DateTime referenceDate, {
  bool compact = false,
}) {
  final birthDate = animal.dateOfBirth;
  if (birthDate != null) {
    final age = compact
        ? AnimalAgeService.formatCompactAge(birthDate, referenceDate)
        : AnimalAgeService.formatMedicalProfileAge(birthDate, referenceDate);
    return animal.isDateOfBirthEstimated ? '$age (estimated)' : age;
  }
  return animal.age == null
      ? 'Not recorded'
      : '${animal.age} yr (legacy estimate)';
}

String _birthDate(Animal animal) {
  final birthDate = animal.dateOfBirth;
  if (birthDate == null) return 'Not recorded';
  final formatted = DateFormat.yMMMMd().format(birthDate);
  return animal.isDateOfBirthEstimated ? 'Estimated: $formatted' : formatted;
}

String _signalment(
  String species,
  String? breed,
  String? sex,
  String currentAge,
) => [
  species,
  if (breed?.isNotEmpty ?? false) breed!,
  if (sex?.isNotEmpty ?? false) sex!,
  if (currentAge != 'Not recorded') currentAge,
].join('  •  ');

const _avatarColors = [
  Color(0xFF2878B5),
  Color(0xFF4A8B69),
  Color(0xFF8A6093),
  Color(0xFFC1784E),
  Color(0xFF397D83),
  Color(0xFF8A6C38),
];
