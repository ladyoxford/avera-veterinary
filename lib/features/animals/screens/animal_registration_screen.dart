import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';

class AnimalRegistrationScreen extends HookConsumerWidget {
  const AnimalRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final hospitalNumber = useTextEditingController();
    final animalName = useTextEditingController();
    final species = useTextEditingController();
    final breed = useTextEditingController();
    final sex = useState('Female');
    final age = useTextEditingController();
    final weight = useTextEditingController();
    final color = useTextEditingController();
    final microchip = useTextEditingController();
    final notes = useTextEditingController();
    final ownerName = useTextEditingController();
    final ownerPhone = useTextEditingController();
    final ownerEmail = useTextEditingController();
    final ownerAddress = useTextEditingController();
    final photoPath = useState<String?>(null);
    final saving = useState(false);

    useEffect(() {
      ref.read(clinicRepositoryProvider).nextHospitalNumber().then((value) {
        hospitalNumber.text = value;
      });
      return null;
    }, const []);

    Future<void> pickPhoto() async {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery);
      photoPath.value = photo?.path;
    }

    Future<void> save() async {
      if (!(formKey.currentState?.validate() ?? false)) return;
      saving.value = true;
      try {
        final repo = ref.read(clinicRepositoryProvider);
        final ownerId = await repo.saveOwner(
          OwnersCompanion.insert(
            fullName: ownerName.text.trim(),
            phone: ownerPhone.text.trim(),
            email: Value(ownerEmail.text.trim().isEmpty ? null : ownerEmail.text.trim()),
            address: Value(ownerAddress.text.trim().isEmpty ? null : ownerAddress.text.trim()),
          ),
        );
        final animalId = await repo.saveAnimal(
          AnimalsCompanion.insert(
            hospitalNumber: hospitalNumber.text.trim(),
            animalName: animalName.text.trim(),
            species: species.text.trim(),
            breed: Value(breed.text.trim().isEmpty ? null : breed.text.trim()),
            sex: Value(sex.value),
            age: Value(int.tryParse(age.text.trim())),
            weight: Value(double.tryParse(weight.text.trim())),
            color: Value(color.text.trim().isEmpty ? null : color.text.trim()),
            microchipNumber: Value(microchip.text.trim().isEmpty ? null : microchip.text.trim()),
            ownerId: ownerId,
            photo: Value(photoPath.value),
            dateRegistered: DateTime.now(),
            notes: Value(notes.text.trim().isEmpty ? null : notes.text.trim()),
          ),
        );
        final offline = ref.read(offlineAuthorizationSnapshotProvider);
        if (offline != null && offline.clinicId != null) {
          await ref.read(offlineSyncRepositoryProvider).enqueue(
            clinicId: offline.clinicId!,
            userId: offline.userId,
            deviceId: await ref.read(offlineAuthorizationServiceProvider).deviceId(),
            entityType: 'patient',
            entityId: animalId.toString(),
            operationType: 'create',
            payload: {
              'localAnimalId': animalId,
              'localOwnerId': ownerId,
              'hospitalNumber': hospitalNumber.text.trim(),
              'animalName': animalName.text.trim(),
              'species': species.text.trim(),
            },
          );
        }
        ref.invalidate(dashboardStatsProvider);
        if (context.mounted) context.push('/animals/$animalId');
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
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
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Field(controller: hospitalNumber, label: 'Hospital Number', icon: Iconsax.hashtag),
                _Field(controller: animalName, label: 'Animal Name', required: true, icon: Iconsax.pet),
                _Field(controller: species, label: 'Species', required: true, icon: Iconsax.category),
                _Field(controller: breed, label: 'Breed', icon: Iconsax.note),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: sex.value,
                    decoration: const InputDecoration(labelText: 'Sex', prefixIcon: Icon(Iconsax.user)),
                    items: const [
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Unknown', child: Text('Unknown')),
                    ],
                    onChanged: (value) => sex.value = value ?? 'Unknown',
                  ),
                ),
                _Field(controller: age, label: 'Age', number: true, icon: Iconsax.timer),
                _Field(controller: weight, label: 'Weight (kg)', number: true, icon: Iconsax.weight),
                _Field(controller: color, label: 'Color', icon: Iconsax.color_swatch),
                _Field(controller: microchip, label: 'Microchip Number', icon: Iconsax.scan_barcode),
              ],
            ),
            const SizedBox(height: 16),
            Text('Owner', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Field(controller: ownerName, label: 'Owner Full Name', required: true, icon: Iconsax.profile_circle),
                _Field(controller: ownerPhone, label: 'Phone', required: true, icon: Iconsax.call),
                _Field(controller: ownerEmail, label: 'Email', icon: Iconsax.sms),
                _Field(controller: ownerAddress, label: 'Address', icon: Iconsax.location),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notes,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Signalment and Notes', prefixIcon: Icon(Iconsax.document_text)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: pickPhoto,
                  icon: const Icon(Iconsax.gallery_add),
                  label: Text(photoPath.value == null ? 'Add Photo' : 'Photo Selected'),
                ),
                FilledButton.icon(
                  onPressed: saving.value ? null : save,
                  icon: saving.value
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Iconsax.save_2),
                  label: const Text('Save Animal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.required = false,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool required;
  final bool number;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextFormField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }
          if (label.startsWith('Weight') &&
              value != null &&
              value.trim().isNotEmpty &&
              (double.tryParse(value) == null || double.parse(value) < 0)) {
            return 'Enter a valid weight';
          }
          return null;
        },
      ),
    );
  }
}
