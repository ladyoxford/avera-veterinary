import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/repositories/clinic_repository.dart';

class ClinicRegistrationScreen extends HookConsumerWidget {
  const ClinicRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final clinicName = useTextEditingController();
    final clinicEmail = useTextEditingController();
    final phone = useTextEditingController();
    final address = useTextEditingController();
    final city = useTextEditingController();
    final country = useTextEditingController(text: 'Nigeria');
    final administrator = useTextEditingController();
    final administratorEmail = useTextEditingController();
    final administratorPhone = useTextEditingController();
    final title = useTextEditingController();
    final plan = useState('Starter');
    final timeZone = useState('Africa/Lagos');
    final accepted = useState(false);
    final submitting = useState(false);

    Future<void> submit() async {
      if (!(formKey.currentState?.validate() ?? false) || !accepted.value) {
        if (!accepted.value) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Accept the Terms of Service and Privacy Policy to continue.',
              ),
            ),
          );
        }
        return;
      }
      submitting.value = true;
      try {
        final application = await ref
            .read(clinicRepositoryProvider)
            .submitClinicApplication(
              ClinicApplication(
                clinicName: clinicName.text,
                clinicEmail: clinicEmail.text,
                phoneNumber: phone.text,
                address: address.text,
                city: city.text,
                country: country.text,
                administratorName: administrator.text,
                administratorEmail: administratorEmail.text,
                administratorPhone: administratorPhone.text,
                professionalTitle: title.text,
                subscriptionPlan: plan.value,
                timeZone: timeZone.value,
              ),
            );
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Application submitted'),
              content: Text(
                'Your clinic registration has been submitted successfully.\n\nReference: ${application.reference}\nPlan: ${application.subscriptionPlan}\nStatus: Pending approval\n\nYour application and payment will be reviewed by the AVERA Platform Owner. You will receive an activation message after approval.',
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    context.go(
                      Uri(
                        path: '/login',
                        queryParameters: {
                          'clinicName': application.clinicName.trim(),
                        },
                      ).toString(),
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } finally {
        submitting.value = false;
      }
    }

    InputDecoration input(String label) => InputDecoration(labelText: label);
    return Scaffold(
      appBar: AppBar(title: const Text('Register Your Clinic')),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              Text(
                'Clinic information',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: clinicName,
                decoration: input('Clinic Name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: clinicEmail,
                decoration: input('Clinic Email Address'),
                keyboardType: TextInputType.emailAddress,
                validator: _email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                decoration: input('Phone Number'),
                keyboardType: TextInputType.phone,
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                decoration: input('Address'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: city,
                      decoration: input('City'),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: country,
                      decoration: input('Country'),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Work Hours', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: timeZone.value,
                decoration: input('Time Zone'),
                items: const [
                  DropdownMenuItem(
                    value: 'Africa/Lagos',
                    child: Text('Africa/Lagos'),
                  ),
                  DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                ],
                onChanged: (value) {
                  if (value != null) timeZone.value = value;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Mon-Sat 08:00-18:00\nSun Closed\nYou can adjust individual days and break periods after approval.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 28),
              Text(
                'Clinic administrator',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: administrator,
                decoration: input('Full Name'),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: administratorEmail,
                decoration: input('Email Address'),
                keyboardType: TextInputType.emailAddress,
                validator: _email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: administratorPhone,
                decoration: input('Phone Number'),
                keyboardType: TextInputType.phone,
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: title,
                decoration: input('Professional Title'),
              ),
              const SizedBox(height: 28),
              Text(
                'Subscription',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: plan.value,
                decoration: input('Selected Subscription Plan'),
                items: const [
                  DropdownMenuItem(value: 'Starter', child: Text('Starter')),
                  DropdownMenuItem(
                    value: 'Professional',
                    child: Text('Professional'),
                  ),
                  DropdownMenuItem(
                    value: 'Enterprise',
                    child: Text('Enterprise'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) plan.value = value;
                },
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: accepted.value,
                onChanged: (value) => accepted.value = value ?? false,
                title: const Text(
                  'I accept the Terms of Service and Privacy Policy.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: submitting.value ? null : submit,
                child: submitting.value
                    ? const CircularProgressIndicator()
                    : const Text('Submit Application'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
  static String? _email(String? value) =>
      value == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(value)
      ? 'Enter a valid email address.'
      : null;
}
