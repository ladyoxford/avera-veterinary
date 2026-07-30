import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/animal_registration_provider.dart';
import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/animal_catalogue.dart';
import '../../../core/services/hospital_numbering.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/catalogue_selector.dart';

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
    final submissionId = useMemoized(() => const Uuid().v4());
    final numberPreview = ref.watch(hospitalNumberPreviewProvider);
    final selection = ref.watch(animalRegistrationSelectionProvider);
    final selectionController = ref.read(
      animalRegistrationSelectionProvider.notifier,
    );
    final clinicName = ref
        .watch(userSessionProvider)
        .valueOrNull
        ?.clinic
        .clinicName;

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
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
      photoPath.value = photo?.path;
    }

    Future<void> save() async {
      final fieldsValid = formKey.currentState?.validate() ?? false;
      final selectionValid = selectionController.validate();
      if (!fieldsValid || !selectionValid) return;
      final resolved = ref.read(animalRegistrationSelectionProvider);
      final speciesName = resolved.resolvedSpeciesName!;
      final breedName = resolved.resolvedBreedName!;
      saving.value = true;
      try {
        final repo = ref.read(clinicRepositoryProvider);
        final session = await ref.read(userSessionProvider.future);
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
            age: Value(int.tryParse(age.text.trim())),
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
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The patient could not be registered. Your form entries are still available.',
              ),
            ),
          );
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
            _RegistrationTextFieldCard(
              controller: age,
              label: 'Age',
              hintText: 'Enter age',
              keyboardType: TextInputType.number,
              validator: _optionalNonNegativeInteger,
            ),
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

String? _optionalNonNegativeInteger(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final parsed = int.tryParse(trimmed);
  return parsed == null || parsed < 0 ? 'Enter a valid age.' : null;
}

String? _optionalNonNegativeNumber(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final parsed = double.tryParse(trimmed);
  return parsed == null || parsed < 0 ? 'Enter a valid weight.' : null;
}
