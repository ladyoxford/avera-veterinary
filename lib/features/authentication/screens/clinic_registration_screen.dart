import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/clinic_registration_provider.dart';
import '../../../core/location/country_catalog.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/subscription_widgets.dart';
import 'clinic_registration_payment_screen.dart';
import 'subscription_comparison_screen.dart';

enum _ClinicRegistrationNextStep { payment, done }

class ClinicRegistrationScreen extends HookConsumerWidget {
  const ClinicRegistrationScreen({super.key});

  static const _timeZones = <String>[
    'Africa/Accra',
    'Africa/Cairo',
    'Africa/Johannesburg',
    'Africa/Lagos',
    'Africa/Nairobi',
    'America/New_York',
    'Asia/Dubai',
    'Europe/London',
    'UTC',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final clinicName = useTextEditingController();
    final clinicEmail = useTextEditingController();
    final phone = useTextEditingController();
    final address = useTextEditingController();
    final city = useTextEditingController();
    final countryCode = useState('NG');
    final country = CountryCatalog.byAlpha2(countryCode.value)!;
    final administrator = useTextEditingController();
    final administratorEmail = useTextEditingController();
    final administratorPhone = useTextEditingController();
    final title = useTextEditingController();
    final timeZone = useState('Africa/Lagos');
    final accepted = useState(false);
    final submitting = useState(false);
    final selectedPlan = ref.watch(clinicRegistrationPlanProvider);

    Future<void> submit() async {
      FocusScope.of(context).unfocus();
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
                country: country.displayName,
                administratorName: administrator.text,
                administratorEmail: administratorEmail.text,
                administratorPhone: administratorPhone.text,
                professionalTitle: title.text,
                subscriptionPlan: selectedPlan.label,
                timeZone: timeZone.value,
              ),
            );
        if (context.mounted) {
          final nextStep = await showDialog<_ClinicRegistrationNextStep>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Application submitted'),
              content: Text(
                'Your clinic application has been submitted successfully.\n\nReference: ${application.reference}\nPlan: ${application.subscriptionPlan}\nStatus: Pending approval\nPayment: ${application.paymentStatus ?? 'Pending'}\n\nContinue to payment to complete your registration request. Platform Owner approval and administrator activation remain separate required steps.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _ClinicRegistrationNextStep.done,
                  ),
                  child: const Text('Done'),
                ),
                if (application.canContinueToPayment)
                  FilledButton(
                    key: const Key('continue-to-registration-payment'),
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      _ClinicRegistrationNextStep.payment,
                    ),
                    child: const Text('Continue to Payment'),
                  ),
              ],
            ),
          );
          if (!context.mounted) return;
          if (nextStep == _ClinicRegistrationNextStep.payment) {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    ClinicRegistrationPaymentScreen(application: application),
              ),
            );
          } else if (nextStep == _ClinicRegistrationNextStep.done) {
            context.go(
              Uri(
                path: '/login',
                queryParameters: {'clinicName': application.clinicName.trim()},
              ).toString(),
            );
          }
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to submit the clinic application right now. Your form has been preserved.',
              ),
            ),
          );
        }
      } finally {
        if (context.mounted) submitting.value = false;
      }
    }

    Future<void> selectCountry() async {
      final value = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            _CountrySelectionSheet(selectedAlpha2: countryCode.value),
      );
      if (value != null) countryCode.value = value;
    }

    Future<void> selectTimeZone() async {
      final value = await _showSearchableSelection(
        context,
        title: 'Select Time Zone',
        options: _timeZones,
        selected: timeZone.value,
      );
      if (value != null) timeZone.value = value;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Your Clinic')),
      body: SafeArea(
        child: Form(
          key: formKey,
          child: ListView(
            key: const Key('clinic-registration-form'),
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              48,
            ),
            children: [
              const AveraPageHeader(
                title: 'Register Your Clinic',
                subtitle: 'Create your AVERA clinic workspace.',
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              const AveraSectionHeader(title: 'Clinic information'),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('clinic-name-field'),
                label: 'Clinic Name',
                hint: 'Enter clinic name',
                controller: clinicName,
                validator: _required,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('clinic-email-field'),
                label: 'Clinic Email Address',
                hint: 'clinic@example.com',
                controller: clinicEmail,
                keyboardType: TextInputType.emailAddress,
                validator: _email,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('clinic-phone-field'),
                label: 'Phone Number',
                hint: 'Enter clinic phone number',
                controller: phone,
                keyboardType: TextInputType.phone,
                validator: _required,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('clinic-address-field'),
                label: 'Address',
                hint: 'Enter clinic address',
                controller: address,
                validator: _required,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackFields = constraints.maxWidth < 680;
                  final cityField = _LabeledTextField(
                    key: const Key('clinic-city-field'),
                    label: 'City',
                    hint: 'Enter city',
                    controller: city,
                    validator: _required,
                  );
                  final countryField = _LabeledSelectionField(
                    key: const Key('clinic-country-field'),
                    label: 'Country',
                    value: country.displayName,
                    onTap: selectCountry,
                  );
                  if (stackFields) {
                    return Column(
                      children: [
                        cityField,
                        const SizedBox(height: AveraSpacing.cardGap),
                        countryField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cityField),
                      const SizedBox(width: AveraSpacing.cardGap),
                      Expanded(child: countryField),
                    ],
                  );
                },
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Work Hours'),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledSelectionField(
                key: const Key('clinic-time-zone-field'),
                label: 'Time Zone',
                value: timeZone.value,
                onTap: selectTimeZone,
              ),
              const SizedBox(height: 10),
              Text(
                'Mon-Sat 08:00-18:00\nSun Closed\nYou can adjust individual days and break periods after approval.',
                style: averaText(context).caption,
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(title: 'Clinic administrator'),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('administrator-name-field'),
                label: 'Full Name',
                hint: 'Administrator full name',
                controller: administrator,
                validator: _required,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('administrator-email-field'),
                label: 'Email Address',
                hint: 'administrator@example.com',
                controller: administratorEmail,
                keyboardType: TextInputType.emailAddress,
                validator: _email,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                key: const Key('administrator-phone-field'),
                label: 'Phone Number',
                hint: 'Administrator phone number',
                controller: administratorPhone,
                keyboardType: TextInputType.phone,
                validator: _required,
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              _LabeledTextField(
                label: 'Professional Title',
                hint: 'Veterinarian, Director, Practice Manager...',
                controller: title,
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              const AveraSectionHeader(
                title: 'Subscription',
                subtitle:
                    'Choose the plan that fits your clinic \u2014 you can upgrade anytime.',
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              SubscriptionPlanSelector(
                selectedPlan: selectedPlan,
                onSelected: (plan) {
                  ref.read(clinicRegistrationPlanProvider.notifier).state =
                      plan;
                },
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('compare-all-features'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ClinicSubscriptionComparisonScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Compare all features'),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('clinic-registration-terms'),
                contentPadding: EdgeInsets.zero,
                value: accepted.value,
                onChanged: (value) => accepted.value = value ?? false,
                title: Text(
                  'I accept the Terms of Service and Privacy Policy.',
                  style: averaText(context).listItemSubtitle,
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              AveraPrimaryActionButton(
                label: 'Continue with ${selectedPlan.label}',
                icon: Icons.arrow_forward_rounded,
                loading: submitting.value,
                onPressed: submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<String?> _showSearchableSelection(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String selected,
  }) => showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SearchSelectionSheet(
      title: title,
      options: options,
      selected: selected,
    ),
  );

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
  static String? _email(String? value) =>
      value == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(value)
      ? 'Enter a valid email address.'
      : null;
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      style: averaText(context).fieldValue,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: averaText(context).fieldPlaceholder,
      ),
    ),
  );
}

class _LabeledSelectionField extends StatelessWidget {
  const _LabeledSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraLabeledFieldCard(
    label: label,
    child: Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(value, style: averaText(context).fieldValue),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SearchSelectionSheet extends StatefulWidget {
  const _SearchSelectionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String selected;

  @override
  State<_SearchSelectionSheet> createState() => _SearchSelectionSheetState();
}

class _CountrySelectionSheet extends StatefulWidget {
  const _CountrySelectionSheet({required this.selectedAlpha2});

  final String selectedAlpha2;

  @override
  State<_CountrySelectionSheet> createState() => _CountrySelectionSheetState();
}

class _CountrySelectionSheetState extends State<_CountrySelectionSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countries = CountryCatalog.search(_query);
    return FractionallySizedBox(
      heightFactor: .86,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          4,
          AveraSpacing.pageHorizontalPadding,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Country', style: averaText(context).sectionTitle),
            const SizedBox(height: 14),
            TextField(
              key: const Key('country-selection-search'),
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search by country or ISO code',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: countries.isEmpty
                  ? Center(
                      child: Text(
                        'No matching countries',
                        style: averaText(context).listItemSubtitle,
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: countries.length,
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        final selected =
                            country.isoAlpha2 == widget.selectedAlpha2;
                        return ListTile(
                          key: Key('country-${country.isoAlpha2}'),
                          title: Text(
                            country.displayName,
                            style: averaText(context).listItemTitle,
                          ),
                          subtitle: Text(
                            '${country.isoAlpha2}  |  ${country.isoAlpha3}',
                            style: averaText(context).listItemSubtitle,
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                          onTap: () =>
                              Navigator.pop(context, country.isoAlpha2),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchSelectionSheetState extends State<_SearchSelectionSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((value) => value.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: .78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          4,
          AveraSpacing.pageHorizontalPadding,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: averaText(context).sectionTitle),
            const SizedBox(height: 14),
            TextField(
              key: const Key('clinic-selection-search'),
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching options',
                        style: averaText(context).listItemSubtitle,
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final value = filtered[index];
                        return ListTile(
                          key: Key('clinic-selection-$value'),
                          title: Text(
                            value,
                            style: averaText(context).listItemTitle,
                          ),
                          trailing: value == widget.selected
                              ? const Icon(Icons.check_circle_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, value),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
