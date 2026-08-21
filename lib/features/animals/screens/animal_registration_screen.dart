import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/animal_registration_provider.dart';
import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/services/animal_age_service.dart';
import '../../../core/services/hospital_numbering.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/avera_photo_actions.dart';
import '../../shared/widgets/catalogue_selector.dart';

typedef PatientPhotoUploader =
    Future<void> Function({
      required String patientId,
      required String contentType,
      required String base64Data,
    });

@visibleForTesting
Future<bool> uploadRegisteredPatientPhoto({
  required XFile photo,
  required String patientId,
  required PatientPhotoUploader upload,
}) async {
  try {
    final bytes = await photo.readAsBytes();
    if (bytes.length > 1024 * 1024) return false;
    await upload(
      patientId: patientId,
      contentType: 'image/jpeg',
      base64Data: base64Encode(bytes),
    );
    return true;
  } catch (_) {
    return false;
  }
}

class AnimalRegistrationScreen extends HookConsumerWidget {
  const AnimalRegistrationScreen({super.key, this.returnResult = false});

  /// Appointment creation keeps its draft on the navigation stack and asks for
  /// the real persisted patient id after a quick registration.
  final bool returnResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final animalName = useTextEditingController();
    final age = useTextEditingController();
    useListenable(age);
    final weight = useTextEditingController();
    final color = useTextEditingController();
    final microchip = useTextEditingController();
    final notes = useTextEditingController();
    final ownerName = useTextEditingController();
    final ownerPhone = useTextEditingController();
    final ownerEmail = useTextEditingController();
    final ownerAddress = useTextEditingController();
    final sex = useState('Female');
    final photoPath = useState<String?>(null);
    final saving = useState(false);
    final ageValidationError = useState<String?>(null);
    final submissionId = useMemoized(() => const Uuid().v4());
    final numberPreview = BackendConfiguration.isConfigured
        ? ref
              .watch(remoteHospitalNumberPreviewProvider)
              .whenData(
                (preview) => HospitalNumberPreview(
                  clinicId: preview.clinicId,
                  prefix: preview.prefix,
                  year: preview.year,
                  sequence: preview.sequence,
                  sequenceLength: preview.sequenceLength,
                  prefixRequiresReview: preview.prefixRequiresReview,
                ),
              )
        : ref.watch(hospitalNumberPreviewProvider);
    final selection = ref.watch(animalRegistrationSelectionProvider);
    final selectionController = ref.read(
      animalRegistrationSelectionProvider.notifier,
    );
    final sessionValue = ref.watch(userSessionProvider).valueOrNull;
    final clinicName = sessionValue?.clinic.clinicName;
    final referenceDate = sessionValue == null
        ? ref.watch(animalAgeReferenceDateProvider)
        : ref.watch(appClockProvider).nowForClinic(sessionValue.clinic);
    final enteredAge = int.tryParse(age.text.trim());
    final previewBirthDate =
        selection.ageInputMode == AnimalAgeInputMode.dateOfBirth
        ? selection.dateOfBirth
        : enteredAge == null ||
              enteredAge < 0 ||
              (enteredAge == 0 && selection.ageUnit != AnimalAgeUnit.days)
        ? null
        : AnimalAgeService.estimateDateOfBirth(
            value: enteredAge,
            unit: selection.ageUnit,
            referenceDate: referenceDate,
          );

    Future<void> selectSpecies() async {
      final selected = await showSearchableCatalogueSelector(
        context: context,
        title: 'Select Species',
        selectedId: selection.selectedSpeciesId,
        options: [
          for (final option in AnimalCatalogue.orderedSpecies)
            CataloguePickerOption(
              id: option.id,
              title: option.displayName,
              subtitle: option.veterinaryName,
              category: option.category.label,
              searchAliases: option.searchAliases,
            ),
        ],
      );
      if (selected != null) selectionController.selectSpecies(selected);
    }

    Future<void> selectBreed() async {
      final species = selection.selectedSpecies;
      if (species == null) return;
      final selected = await showSearchableCatalogueSelector(
        context: context,
        title:
            'Select ${species.displayName} ${AnimalCatalogue.breedFieldLabel(species)}',
        selectedId: selection.selectedBreedId,
        options: [
          for (final option in selection.availableBreeds)
            CataloguePickerOption(
              id: option.id,
              title: option.displayName,
              searchAliases: option.aliases,
            ),
        ],
      );
      if (selected != null) selectionController.selectBreed(selected);
    }

    Future<void> pickPhoto() async {
      final photo = await pickAndCropAveraPhoto(AveraPhotoAction.uploadPhoto);
      photoPath.value = photo?.path;
    }

    Future<void> selectDateOfBirth() async {
      final selected = await showDatePicker(
        context: context,
        initialDate: selection.dateOfBirth ?? referenceDate,
        firstDate: DateTime(referenceDate.year - 100),
        lastDate: referenceDate,
        helpText: 'Select Date of Birth',
      );
      if (selected == null) return;
      selectionController.setDateOfBirth(selected);
      ageValidationError.value = null;
    }

    Future<void> save() async {
      ageValidationError.value = _validateAgeSelection(
        selection: selection,
        ageText: age.text,
        referenceDate: referenceDate,
      );
      final fieldsValid = formKey.currentState?.validate() ?? false;
      final selectionValid = selectionController.validate();
      if (!fieldsValid || !selectionValid || ageValidationError.value != null) {
        return;
      }
      final resolved = ref.read(animalRegistrationSelectionProvider);
      final speciesName = resolved.resolvedSpeciesName!;
      final breedName = resolved.resolvedBreedName!;
      saving.value = true;
      try {
        final repo = ref.read(clinicRepositoryProvider);
        final session = await ref.read(userSessionProvider.future);
        final registrationDate = ref
            .read(appClockProvider)
            .nowForClinic(session.clinic);
        final originalAge = int.tryParse(age.text.trim());
        final dateOfBirth =
            resolved.ageInputMode == AnimalAgeInputMode.dateOfBirth
            ? resolved.dateOfBirth!
            : AnimalAgeService.estimateDateOfBirth(
                value: originalAge!,
                unit: resolved.ageUnit,
                referenceDate: registrationDate,
              );
        final isEstimated =
            resolved.ageInputMode == AnimalAgeInputMode.currentAge ||
            resolved.isDateOfBirthEstimated;
        if (BackendConfiguration.isConfigured) {
          final registration = await ref
              .read(clinicalRemoteDataSourceProvider)
              .registerPatient({
                'submissionId': submissionId,
                'name': animalName.text.trim(),
                'species': speciesName,
                'speciesId': resolved.selectedSpeciesId,
                'breed': breedName,
                'breedId': resolved.selectedBreedId,
                'sex': sex.value,
                'dateOfBirth': DateFormat('yyyy-MM-dd').format(dateOfBirth),
                'isDateOfBirthEstimated': isEstimated,
                'originalAgeValue':
                    resolved.ageInputMode == AnimalAgeInputMode.currentAge
                    ? originalAge
                    : null,
                'originalAgeUnit':
                    resolved.ageInputMode == AnimalAgeInputMode.currentAge
                    ? resolved.ageUnit.storageValue
                    : null,
                'weightKg': double.tryParse(weight.text.trim()),
                'colour': _nullIfEmpty(color.text),
                'microchipNumber': _nullIfEmpty(microchip.text),
                'notes': _nullIfEmpty(notes.text),
                'owner': {
                  'fullName': ownerName.text.trim(),
                  'phone': ownerPhone.text.trim(),
                  'email': _nullIfEmpty(ownerEmail.text),
                  'address': _nullIfEmpty(ownerAddress.text),
                },
              });
          var photoUploaded = true;
          final selectedPhotoPath = photoPath.value;
          if (selectedPhotoPath != null) {
            photoUploaded = await uploadRegisteredPatientPhoto(
              photo: XFile(selectedPhotoPath),
              patientId: registration.patient.id,
              upload: ref
                  .read(clinicalRemoteDataSourceProvider)
                  .updatePatientPhoto,
            );
          }
          await ref.read(remotePatientListProvider.notifier).refresh();
          await ref.read(remotePatientDirectoryProvider.notifier).refresh();
          ref
            ..invalidate(remoteDashboardProvider)
            ..invalidate(
              remotePatientMedicalFileProvider(registration.patient.id),
            )
            ..invalidate(remoteHospitalNumberPreviewProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  photoUploaded
                      ? 'Patient registered successfully as ${registration.patient.hospitalNumber}.'
                      : 'Patient registered as ${registration.patient.hospitalNumber}, but the photo could not be uploaded. You can add it from the Medical File.',
                ),
              ),
            );
            if (returnResult) {
              context.pop(registration.patient.id);
            } else {
              context.push('/animals/${registration.patient.id}');
            }
          }
          return;
        }
        final assignment = await repo.registerAnimalWithHospitalNumber(
          session: session,
          submissionId: submissionId,
          speciesId: resolved.selectedSpeciesId,
          breedId: resolved.selectedBreedId,
          owner: OwnersCompanion.insert(
            fullName: ownerName.text.trim(),
            phone: ownerPhone.text.trim(),
            email: Value(_nullIfEmpty(ownerEmail.text)),
            address: Value(_nullIfEmpty(ownerAddress.text)),
          ),
          animal: AnimalsCompanion(
            animalName: Value(animalName.text.trim()),
            species: Value(speciesName),
            breed: Value(breedName),
            sex: Value(sex.value),
            age: const Value(null),
            dateOfBirth: Value(dateOfBirth),
            isDateOfBirthEstimated: Value(isEstimated),
            originalAgeValue:
                resolved.ageInputMode == AnimalAgeInputMode.currentAge
                ? Value(originalAge)
                : const Value(null),
            originalAgeUnit:
                resolved.ageInputMode == AnimalAgeInputMode.currentAge
                ? Value(resolved.ageUnit.storageValue)
                : const Value(null),
            ageRecordedAt: Value(registrationDate),
            weight: Value(double.tryParse(weight.text.trim())),
            color: Value(_nullIfEmpty(color.text)),
            microchipNumber: Value(_nullIfEmpty(microchip.text)),
            photo: Value(photoPath.value),
            notes: Value(_nullIfEmpty(notes.text)),
          ),
        );
        final offline = ref.read(offlineAuthorizationSnapshotProvider);
        if (offline != null && offline.clinicId != null) {
          await ref
              .read(offlineSyncRepositoryProvider)
              .enqueue(
                clinicId: offline.clinicId!,
                userId: offline.userId,
                deviceId: await ref
                    .read(offlineAuthorizationServiceProvider)
                    .deviceId(),
                entityType: 'patient',
                entityId: assignment.patientId.toString(),
                operationType: 'create',
                payload: {
                  'localAnimalId': assignment.patientId,
                  'hospitalNumber': assignment.hospitalNumber,
                  'animalName': animalName.text.trim(),
                  'species': speciesName,
                  'breed': breedName,
                  'dateOfBirth': dateOfBirth.toIso8601String(),
                  'isDateOfBirthEstimated': isEstimated,
                },
              );
        }
        ref
          ..invalidate(dashboardStatsProvider)
          ..invalidate(animalSearchProvider)
          ..invalidate(hospitalNumberPreviewProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Patient registered successfully as ${assignment.hospitalNumber}.',
              ),
            ),
          );
          if (returnResult) {
            context.pop(assignment.patientId);
          } else {
            context.push('/animals/${assignment.patientId}');
          }
        }
      } catch (error) {
        if (context.mounted) {
          final message = error is ApiException
              ? error.message
              : 'The patient could not be registered. Your form entries are still available.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      } finally {
        saving.value = false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Animal')),
      body: Form(
        key: formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.pageTopPadding,
            AveraSpacing.pageHorizontalPadding,
            AveraSpacing.bottomContentClearance,
          ),
          children: [
            AveraPageHeader(
              title: 'Register Animal',
              subtitle:
                  '${clinicName ?? 'Active clinic'} - New patient registration',
            ),
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            _HospitalNumberPreview(preview: numberPreview),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              key: const Key('animal-name-field'),
              controller: animalName,
              label: 'Animal Name',
              hintText: 'Enter animal name',
              required: true,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _SelectionFieldCard(
              key: const Key('species-selection-field'),
              label: 'Species',
              value: selection.selectedSpecies?.displayLabel,
              hintText: 'Select Species',
              errorText: selection.speciesValidationError,
              onTap: selectSpecies,
            ),
            if (selection.requiresCustomSpecies) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              _RegistrationTextFieldCard(
                key: const Key('custom-species-field'),
                label: 'Enter Species',
                hintText: 'Enter animal species',
                initialValue: selection.customSpeciesName,
                onChanged: selectionController.setCustomSpecies,
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            _SelectionFieldCard(
              key: const Key('breed-selection-field'),
              label: AnimalCatalogue.breedFieldLabel(selection.selectedSpecies),
              value: selection.selectedBreed?.displayName,
              hintText: selection.selectedSpecies == null
                  ? 'Select a species first'
                  : 'Select Breed',
              errorText: selection.breedValidationError,
              onTap: selection.selectedSpecies == null ? null : selectBreed,
            ),
            if (selection.requiresCustomBreed) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              _RegistrationTextFieldCard(
                key: const Key('custom-breed-field'),
                label: 'Enter Breed',
                hintText: 'Enter breed or variety',
                initialValue: selection.customBreedName,
                onChanged: selectionController.setCustomBreed,
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            AveraLabeledFieldCard(
              label: 'Sex',
              child: DropdownButtonFormField<String>(
                value: sex.value,
                isExpanded: true,
                style: averaText(context).fieldValue,
                decoration: const InputDecoration.collapsed(hintText: ''),
                items: const [
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                ],
                onChanged: (value) => sex.value = value ?? 'Unknown',
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            Text('AGE / DATE OF BIRTH', style: averaText(context).sectionLabel),
            const SizedBox(height: 8),
            SegmentedButton<AnimalAgeInputMode>(
              key: const Key('age-input-mode-selector'),
              segments: const [
                ButtonSegment(
                  value: AnimalAgeInputMode.dateOfBirth,
                  label: Text('Date of Birth'),
                  icon: Icon(Icons.cake_outlined),
                ),
                ButtonSegment(
                  value: AnimalAgeInputMode.currentAge,
                  label: Text('Current Age'),
                  icon: Icon(Icons.timelapse_rounded),
                ),
              ],
              selected: {selection.ageInputMode},
              onSelectionChanged: (value) {
                selectionController.setAgeInputMode(value.single);
                ageValidationError.value = null;
              },
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            if (selection.ageInputMode == AnimalAgeInputMode.dateOfBirth) ...[
              AveraLabeledFieldCard(
                label: 'Date of Birth',
                child: InkWell(
                  key: const Key('date-of-birth-field'),
                  onTap: selectDateOfBirth,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selection.dateOfBirth == null
                              ? 'Select date'
                              : DateFormat.yMMMMd().format(
                                  selection.dateOfBirth!,
                                ),
                          style: selection.dateOfBirth == null
                              ? averaText(context).fieldPlaceholder
                              : averaText(context).fieldValue,
                        ),
                      ),
                      const Icon(Icons.calendar_month_outlined),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              AveraLabeledSwitchField(
                label: 'Date Accuracy',
                title: 'Date of birth is estimated',
                subtitle:
                    'The record will identify this date as an approximation.',
                value: selection.isDateOfBirthEstimated,
                onChanged: selectionController.setDateOfBirthEstimated,
              ),
            ] else ...[
              _RegistrationTextFieldCard(
                key: const Key('current-age-field'),
                controller: age,
                label: 'Age',
                hintText: 'Enter current age',
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  ageValidationError.value = null;
                },
                validator: (value) =>
                    _validateCurrentAge(value, selection.ageUnit),
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              AveraLabeledDropdownField<AnimalAgeUnit>(
                label: 'Age Unit',
                hintText: 'Select age unit',
                value: selection.ageUnit,
                items: [
                  for (final unit in AnimalAgeUnit.values)
                    DropdownMenuItem(
                      value: unit,
                      child: Text(unit.pluralLabel),
                    ),
                ],
                onChanged: (unit) {
                  if (unit != null) selectionController.setAgeUnit(unit);
                  ageValidationError.value = null;
                },
              ),
            ],
            if (ageValidationError.value != null) ...[
              const SizedBox(height: 8),
              Text(
                ageValidationError.value!,
                style: averaText(
                  context,
                ).caption.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (previewBirthDate != null &&
                !AnimalAgeService.isFutureBirthDate(
                  previewBirthDate,
                  referenceDate,
                )) ...[
              const SizedBox(height: AveraSpacing.cardGap),
              AveraSurfaceCard(
                outlined: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selection.ageInputMode == AnimalAgeInputMode.currentAge)
                      Text(
                        'Estimated date of birth: '
                        '${DateFormat.yMMMMd().format(previewBirthDate)}',
                        key: const Key('estimated-birth-date-preview'),
                        style: averaText(context).fieldValue,
                      ),
                    if (selection.ageInputMode == AnimalAgeInputMode.currentAge)
                      const SizedBox(height: 6),
                    Text(
                      'Current age: '
                      '${AnimalAgeService.formatDetailedAge(previewBirthDate, referenceDate)}',
                      key: const Key('current-age-preview'),
                      style: averaText(context).caption,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: weight,
              label: 'Weight',
              hintText: 'Enter weight in kg',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _optionalNonNegativeNumber,
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: color,
              label: 'Color / Coat Pattern',
              hintText: 'Example: Ginger / Orange Tabby',
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: microchip,
              label: 'Microchip Number',
              hintText: 'Enter microchip number',
            ),
            const SizedBox(height: AveraSpacing.sectionGap),
            const AveraSectionHeader(
              title: 'Owner Information',
              subtitle: 'Contact and ownership details',
            ),
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            _RegistrationTextFieldCard(
              controller: ownerName,
              label: 'Owner Full Name',
              hintText: 'Enter owner full name',
              required: true,
              autofillHints: const [AutofillHints.name],
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: ownerPhone,
              label: 'Phone Number',
              hintText: 'Enter phone number',
              required: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: ownerEmail,
              label: 'Email Address',
              hintText: 'owner@example.com',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: ownerAddress,
              label: 'Address',
              hintText: 'Enter address',
              autofillHints: const [AutofillHints.fullStreetAddress],
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            _RegistrationTextFieldCard(
              controller: notes,
              label: 'Signalment and Notes',
              hintText: 'Enter relevant signalment, alerts, or notes',
              minLines: 3,
              maxLines: 6,
            ),
            const SizedBox(height: AveraSpacing.subtitleToContentGap),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-photo-button'),
                onPressed: saving.value ? null : pickPhoto,
                icon: const Icon(Iconsax.gallery_add),
                label: Text(
                  photoPath.value == null ? 'Add Photo' : 'Photo Selected',
                  style: averaText(context).buttonLabel,
                ),
              ),
            ),
            const SizedBox(height: AveraSpacing.cardGap),
            AveraPrimaryActionButton(
              key: const Key('register-animal-button'),
              label: 'Register Animal',
              icon: Iconsax.save_2,
              loading: saving.value,
              onPressed: save,
            ),
          ],
        ),
      ),
    );
  }
}

class _HospitalNumberPreview extends StatelessWidget {
  const _HospitalNumberPreview({required this.preview});
  final AsyncValue<HospitalNumberPreview> preview;

  @override
  Widget build(BuildContext context) => Semantics(
    readOnly: true,
    label: 'Hospital Number',
    child: AveraLabeledFieldCard(
      label: 'Hospital Number',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview.when(
            loading: () => const Row(
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Preparing hospital number...')),
              ],
            ),
            error: (_, __) => Text(
              'Numbering configuration needs attention.',
              style: averaText(context).fieldPlaceholder,
            ),
            data: (value) => Text(
              value.hospitalNumber,
              style: averaText(
                context,
              ).fieldValue.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Automatically assigned from this clinic\'s patient-number sequence.',
            style: averaText(context).caption,
          ),
        ],
      ),
    ),
  );
}

class _RegistrationTextFieldCard extends StatelessWidget {
  const _RegistrationTextFieldCard({
    super.key,
    required this.label,
    required this.hintText,
    this.controller,
    this.initialValue,
    this.required = false,
    this.keyboardType,
    this.autofillHints,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.validator,
  });

  final String label;
  final String hintText;
  final TextEditingController? controller;
  final String? initialValue;
  final bool required;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      minLines: minLines,
      maxLines: maxLines,
      style: averaText(context).fieldValue,
      decoration: InputDecoration.collapsed(
        hintText: hintText,
        hintStyle: averaText(context).fieldPlaceholder,
      ),
      onChanged: onChanged,
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Please enter $label.';
        }
        return validator?.call(value);
      },
    ),
  );
}

class _SelectionFieldCard extends StatelessWidget {
  const _SelectionFieldCard({
    super.key,
    required this.label,
    required this.value,
    required this.hintText,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final String? value;
  final String hintText;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AveraLabeledFieldCard(
        label: label,
        child: Semantics(
          button: onTap != null,
          enabled: onTap != null,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AveraSpacing.minimumTapTarget,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? hintText,
                      style: value == null
                          ? averaText(context).fieldPlaceholder
                          : averaText(context).fieldValue,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: onTap == null
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (errorText != null) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            errorText!,
            style: averaText(
              context,
            ).caption.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ],
  );
}

String? _nullIfEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _validateCurrentAge(String? value, AnimalAgeUnit unit) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Please enter the current age.';
  final parsed = int.tryParse(trimmed);
  if (parsed == null || parsed < 0) {
    return 'Age must be a whole number.';
  }
  if (parsed == 0 && unit != AnimalAgeUnit.days) {
    return 'Use 0 days for an animal born today.';
  }
  return null;
}

String? _validateAgeSelection({
  required AnimalRegistrationSelectionState selection,
  required String ageText,
  required DateTime referenceDate,
}) {
  if (selection.ageInputMode == AnimalAgeInputMode.currentAge) {
    return _validateCurrentAge(ageText, selection.ageUnit);
  }
  final birthDate = selection.dateOfBirth;
  if (birthDate == null) return 'Please select a date of birth.';
  if (AnimalAgeService.isFutureBirthDate(birthDate, referenceDate)) {
    return 'Date of birth cannot be in the future.';
  }
  return null;
}

String? _optionalNonNegativeNumber(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final parsed = double.tryParse(trimmed);
  return parsed == null || parsed < 0 ? 'Enter a valid weight.' : null;
}
