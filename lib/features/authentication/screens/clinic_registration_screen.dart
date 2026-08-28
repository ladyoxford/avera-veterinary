import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/clinic_registration_provider.dart';
import '../../../core/location/country_catalog.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/subscription/subscription_plan_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../../shared/widgets/avera_auth_ui.dart';
import '../../shared/widgets/subscription_widgets.dart';
import 'clinic_registration_review_screen.dart';
import 'subscription_comparison_screen.dart';

class ClinicRegistrationScreen extends HookConsumerWidget {
  const ClinicRegistrationScreen({
    super.key,
    this.initialApplication,
    this.initialAccountEmail,
  });

  final ClinicApplication? initialApplication;
  final String? initialAccountEmail;

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
    final clinicName = useTextEditingController(
      text: initialApplication?.clinicName,
    );
    final accountEmail = useTextEditingController(
      text: initialApplication?.accountEmail ?? initialAccountEmail,
    );
    final phone = useTextEditingController(
      text: initialApplication?.phoneNumber,
    );
    final address = useTextEditingController(text: initialApplication?.address);
    final city = useTextEditingController(text: initialApplication?.city);
    final initialCountry = CountryCatalog.all.where(
      (item) => item.displayName == initialApplication?.country,
    );
    final countryCode = useState(
      initialCountry.isNotEmpty ? initialCountry.first.isoAlpha2 : 'NG',
    );
    final country = CountryCatalog.byAlpha2(countryCode.value)!;
    final administrator = useTextEditingController(
      text: initialApplication?.administratorName,
    );
    final administratorPhone = useTextEditingController(
      text: initialApplication?.administratorPhone,
    );
    final title = useTextEditingController(
      text: initialApplication?.professionalTitle,
    );
    final timeZone = useState(initialApplication?.timeZone ?? 'Africa/Lagos');
    final accepted = useState(false);
    final submitting = useState(false);
    final activeDraft = useState<ClinicApplication?>(initialApplication);
    final restored = useState(initialApplication != null);
    final selectedPlan = ref.watch(clinicRegistrationPlanProvider);

    useEffect(() {
      final initialPlan = SubscriptionPlan.values.where(
        (item) => item.label == initialApplication?.subscriptionPlan,
      );
      if (initialPlan.isNotEmpty) {
        ref.read(clinicRegistrationPlanProvider.notifier).state =
            initialPlan.first;
      }
      if (restored.value) return null;
      unawaited(() async {
        final draft = await ref
            .read(clinicRegistrationDraftStoreProvider)
            .load();
        if (draft == null || !context.mounted) {
          restored.value = true;
          return;
        }
        activeDraft.value = draft;
        clinicName.text = draft.clinicName;
        accountEmail.text = draft.accountEmail;
        phone.text = draft.phoneNumber;
        address.text = draft.address;
        city.text = draft.city;
        administrator.text = draft.administratorName;
        administratorPhone.text = draft.administratorPhone;
        title.text = draft.professionalTitle;
        timeZone.value = draft.timeZone;
        final matchingCountry = CountryCatalog.all.where(
          (item) => item.displayName == draft.country,
        );
        if (matchingCountry.isNotEmpty) {
          countryCode.value = matchingCountry.first.isoAlpha2;
        }
        final plan = SubscriptionPlan.values.where(
          (item) => item.label == draft.subscriptionPlan,
        );
        if (plan.isNotEmpty) {
          ref.read(clinicRegistrationPlanProvider.notifier).state = plan.first;
        }
        restored.value = true;
      }());
      return null;
    }, const []);

    Future<void> submit() async {
      if (submitting.value) return;
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
        final pending = ClinicApplication(
          clinicName: clinicName.text,
          accountEmail: accountEmail.text,
          phoneNumber: phone.text,
          address: address.text,
          city: city.text,
          country: country.displayName,
          administratorName: administrator.text,
          administratorPhone: administratorPhone.text,
          professionalTitle: title.text,
          subscriptionPlan: selectedPlan.label,
          timeZone: timeZone.value,
          applicationId: activeDraft.value?.applicationId,
          clinicId: activeDraft.value?.clinicId,
          reference: activeDraft.value?.reference,
          paymentStatus: activeDraft.value?.paymentStatus,
          paymentAccessToken: activeDraft.value?.paymentAccessToken,
          draftAccessToken: activeDraft.value?.draftAccessToken,
          status: activeDraft.value?.status,
        );
        final application = await ref
            .read(clinicRepositoryProvider)
            .submitClinicApplication(pending);
        activeDraft.value = application;
        await ref.read(clinicRegistrationDraftStoreProvider).save(application);
        if (context.mounted) {
          await Navigator.of(context).push<ClinicRegistrationReviewAction>(
            MaterialPageRoute(
              builder: (_) =>
                  ClinicRegistrationReviewScreen(application: application),
            ),
          );
        }
      } on ApiException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_registrationFailureMessage(error))),
          );
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

    if (!restored.value) {
      return const AveraAuthScaffold(
        backTitle: 'Register Your Clinic',
        showBrand: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return AveraAuthScaffold(
      backTitle: 'Register Your Clinic',
      showBrand: false,
      child: Form(
        key: formKey,
        child: Column(
          key: const Key('clinic-registration-form'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create your AVERA clinic workspace.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            const _AuthSectionTitle('Clinic Information'),
            const SizedBox(height: 12),
            AveraAuthCard(
              child: Column(
                children: [
                  AveraAuthField(
                    key: const Key('clinic-name-field'),
                    label: 'Clinic Name',
                    hintText: 'Enter clinic name',
                    controller: clinicName,
                    icon: Icons.local_hospital_outlined,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 20),
                  AveraAuthField(
                    key: const Key('clinic-phone-field'),
                    label: 'Phone Number',
                    hintText: 'Enter clinic phone number',
                    controller: phone,
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 20),
                  AveraAuthField(
                    key: const Key('clinic-address-field'),
                    label: 'Address',
                    hintText: 'Enter clinic address',
                    controller: address,
                    icon: Icons.location_on_outlined,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cityField = AveraAuthField(
                        key: const Key('clinic-city-field'),
                        label: 'City',
                        hintText: 'Enter city',
                        controller: city,
                        icon: Icons.location_city_outlined,
                        textInputAction: TextInputAction.next,
                        validator: _required,
                      );
                      final countryField = _AuthSelectionField(
                        key: const Key('clinic-country-field'),
                        label: 'Country',
                        value: country.displayName,
                        icon: Icons.public_outlined,
                        onTap: selectCountry,
                      );
                      if (constraints.maxWidth < 500) {
                        return Column(
                          children: [
                            cityField,
                            const SizedBox(height: 20),
                            countryField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: cityField),
                          const SizedBox(width: 16),
                          Expanded(child: countryField),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const _AuthSectionTitle('Work Hours'),
            const SizedBox(height: 12),
            AveraAuthCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AuthSelectionField(
                    key: const Key('clinic-time-zone-field'),
                    label: 'Time Zone',
                    value: timeZone.value,
                    icon: Icons.schedule_outlined,
                    onTap: selectTimeZone,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mon-Sat 08:00-18:00 | Sun Closed',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Individual days and break periods can be adjusted after approval.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const _AuthSectionTitle('Clinic Administrator'),
            const SizedBox(height: 12),
            AveraAuthCard(
              child: Column(
                children: [
                  AveraAuthField(
                    key: const Key('administrator-name-field'),
                    label: 'Full Name',
                    hintText: 'Administrator full name',
                    controller: administrator,
                    icon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 20),
                  AveraAuthField(
                    key: const Key('account-email-field'),
                    label: 'Account Email',
                    hintText: 'administrator@example.com',
                    controller: accountEmail,
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    helperText:
                        'Used for sign-in, clinic activation and registration updates.',
                    validator: _email,
                  ),
                  const SizedBox(height: 20),
                  AveraAuthField(
                    key: const Key('administrator-phone-field'),
                    label: 'Phone Number',
                    hintText: 'Administrator phone number',
                    controller: administratorPhone,
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 20),
                  AveraAuthField(
                    key: const Key('administrator-title-field'),
                    label: 'Professional Title',
                    hintText: 'Veterinarian, Director, Practice Manager...',
                    controller: title,
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const _AuthSectionTitle('Subscription'),
            const SizedBox(height: 5),
            Text(
              'Choose the plan that fits your clinic. You can upgrade later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SubscriptionPlanSelector(
              selectedPlan: selectedPlan,
              onSelected: (plan) {
                ref.read(clinicRegistrationPlanProvider.notifier).state = plan;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('compare-all-features'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const ClinicSubscriptionComparisonScreen(),
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Compare all features'),
              ),
            ),
            CheckboxListTile(
              key: const Key('clinic-registration-terms'),
              contentPadding: EdgeInsets.zero,
              value: accepted.value,
              onChanged: submitting.value
                  ? null
                  : (value) => accepted.value = value ?? false,
              title: Text(
                'I accept the Terms of Service and Privacy Policy.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 14),
            AveraPrimaryActionButton(
              key: const Key('review-and-continue'),
              label: 'Review & Continue',
              icon: Icons.arrow_forward_rounded,
              loading: submitting.value,
              onPressed: submit,
            ),
          ],
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

String _registrationFailureMessage(ApiException error) {
  if (error.code == 'application_exists') {
    return 'An active clinic application already exists for this administrator email. Contact AVERA support if you need to resume its payment. Your form has been preserved.';
  }
  return '${error.message} Your form has been preserved.';
}

class _AuthSectionTitle extends StatelessWidget {
  const _AuthSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _AuthSelectionField extends StatelessWidget {
  const _AuthSelectionField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AveraFormLabel(label),
        const SizedBox(height: 9),
        Semantics(
          button: true,
          label: '$label, $value',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(icon, color: colors.onSurfaceVariant),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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
