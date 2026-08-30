import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/subscription/registration_payment_session_store.dart';
import '../../../core/subscription/subscription_payment_gateway.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

typedef RegistrationPaymentCheckoutLauncher = Future<bool> Function(Uri uri);

final registrationPaymentCheckoutLauncherProvider =
    Provider<RegistrationPaymentCheckoutLauncher>(
      (ref) =>
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

class ClinicRegistrationPaymentScreen extends ConsumerStatefulWidget {
  const ClinicRegistrationPaymentScreen({super.key, required this.application});

  final ClinicApplication application;

  @override
  ConsumerState<ClinicRegistrationPaymentScreen> createState() =>
      _ClinicRegistrationPaymentScreenState();
}

class _ClinicRegistrationPaymentScreenState
    extends ConsumerState<ClinicRegistrationPaymentScreen> {
  SubscriptionBillingCycle _billingCycle = SubscriptionBillingCycle.monthly;
  SubscriptionBillingPlan? _billingPlan;
  String? _paymentReference;
  String? _error;
  String? _planError;
  SubscriptionPaymentVerification? _verification;
  bool _loadingPlan = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSession();
      _loadPaymentPlan();
    });
  }

  Future<void> _loadPaymentPlan() async {
    final applicationId = widget.application.applicationId;
    final accessToken = widget.application.paymentAccessToken;
    if (applicationId == null || accessToken == null) {
      if (mounted) {
        setState(() {
          _loadingPlan = false;
          _planError = 'Pricing is unavailable for this payment session.';
        });
      }
      return;
    }
    try {
      final plan = await ref
          .read(subscriptionPaymentGatewayProvider)
          .loadRegistrationPaymentPlan(
            applicationId: applicationId,
            accessToken: accessToken,
          );
      if (!mounted) return;
      setState(() {
        _billingPlan = plan;
        _loadingPlan = false;
        _planError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = _paymentError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPlan = false;
        _planError = _unexpectedPaymentError;
      });
    }
  }

  Future<void> _restoreSession() async {
    final session = await ref
        .read(registrationPaymentSessionStoreProvider)
        .loadActive();
    if (!mounted ||
        session?.applicationId != widget.application.applicationId) {
      return;
    }
    setState(() {
      _paymentReference = session!.paymentReference;
      _billingCycle = session.billingCycle == 'annual'
          ? SubscriptionBillingCycle.annual
          : SubscriptionBillingCycle.monthly;
    });
  }

  Future<void> _startCheckout({bool retry = false}) async {
    if (_working) return;
    final applicationId = widget.application.applicationId;
    final clinicId = widget.application.clinicId;
    final accessToken = widget.application.paymentAccessToken;
    final applicationReference = widget.application.reference;
    if (applicationId == null ||
        clinicId == null ||
        accessToken == null ||
        applicationReference == null) {
      setState(
        () => _error =
            'This clinic payment session is unavailable. Your application remains submitted.',
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final checkout = await ref
          .read(subscriptionPaymentGatewayProvider)
          .initializeRegistrationCheckout(
            applicationId: applicationId,
            accessToken: accessToken,
            billingCycle: _billingCycle,
            retry: retry,
          );
      await ref
          .read(registrationPaymentSessionStoreProvider)
          .save(
            RegistrationPaymentSession(
              applicationId: applicationId,
              clinicId: clinicId,
              applicationReference: applicationReference,
              plan: widget.application.subscriptionPlan,
              accessToken: accessToken,
              paymentReference: checkout.reference,
              billingCycle: _billingCycle.apiValue,
            ),
          );
      if (!mounted) return;
      setState(() => _paymentReference = checkout.reference);
      final opened = await ref
          .read(registrationPaymentCheckoutLauncherProvider)
          .call(checkout.authorizationUrl);
      if (!opened) {
        throw const ApiException(
          'checkout_unavailable',
          'The secure payment page could not be opened.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Paystack checkout opened. Return to AVERA to confirm payment.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _paymentError(error));
    } catch (_) {
      if (mounted) setState(() => _error = _unexpectedPaymentError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _verifyPayment() async {
    if (_working) return;
    final applicationId = widget.application.applicationId;
    final accessToken = widget.application.paymentAccessToken;
    final reference = _paymentReference;
    if (applicationId == null || accessToken == null || reference == null) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final verification = await ref
          .read(subscriptionPaymentGatewayProvider)
          .verifyRegistrationPayment(
            applicationId: applicationId,
            accessToken: accessToken,
            reference: reference,
          );
      if (!verification.verified) {
        throw const ApiException(
          'payment_pending',
          'Paystack has not confirmed this payment yet.',
        );
      }
      await ref.read(registrationPaymentSessionStoreProvider).clear();
      await ref.read(clinicRegistrationDraftStoreProvider).clear();
      if (mounted) setState(() => _verification = verification);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _paymentError(error));
    } catch (_) {
      if (mounted) setState(() => _error = _unexpectedPaymentError);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = _verification != null;
    final amount = _billingPlan?.amountFor(_billingCycle);
    final checkoutConfigured =
        _billingPlan?.checkoutConfiguredFor(_billingCycle) == true;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Complete Payment')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              40,
            ),
            children: [
              if (verified)
                AveraPageHeader(
                  title: 'Payment confirmed',
                  subtitle: _verification!.applicationApproved
                      ? 'Your clinic has been approved. Check the administrator email for the activation link.'
                      : 'Your clinic application is awaiting approval.',
                )
              else
                Text(
                  'Complete the payment step for your submitted clinic application.',
                  style: averaText(context).listItemSubtitle,
                ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              AveraSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryLine(
                      label: 'Application reference',
                      value: widget.application.reference ?? 'Unavailable',
                    ),
                    const SizedBox(height: 12),
                    _SummaryLine(
                      label: 'Selected plan',
                      value: widget.application.subscriptionPlan,
                    ),
                    const SizedBox(height: 12),
                    _SummaryLine(
                      label: 'Approval status',
                      value: _verification?.applicationApproved == true
                          ? 'Approved'
                          : 'Pending approval',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AveraSpacing.sectionGap),
              if (!verified) ...[
                const AveraSectionHeader(title: 'Billing cycle'),
                const SizedBox(height: AveraSpacing.cardGap),
                SegmentedButton<SubscriptionBillingCycle>(
                  segments: const [
                    ButtonSegment(
                      value: SubscriptionBillingCycle.monthly,
                      label: Text('Monthly'),
                    ),
                    ButtonSegment(
                      value: SubscriptionBillingCycle.annual,
                      label: Text('Annual'),
                    ),
                  ],
                  selected: {_billingCycle},
                  onSelectionChanged: _paymentReference == null && !_working
                      ? (value) => setState(() {
                          _billingCycle = value.single;
                          _error = null;
                        })
                      : null,
                ),
                const SizedBox(height: AveraSpacing.cardGap),
                if (_loadingPlan)
                  const AveraSurfaceCard(
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text('Loading secure plan pricing…')),
                      ],
                    ),
                  )
                else if (_planError != null)
                  AveraSurfaceCard(
                    outlined: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _planError!,
                          style: averaText(context).listItemSubtitle,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _loadPaymentPlan,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry pricing'),
                        ),
                      ],
                    ),
                  )
                else if (amount != null)
                  AveraSurfaceCard(
                    key: const Key('registration-selected-price'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_billingPlan!.name} ${_billingCycle == SubscriptionBillingCycle.monthly ? 'Monthly' : 'Annual'}',
                                style: averaText(context).listItemTitle,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _billingCycle ==
                                        SubscriptionBillingCycle.monthly
                                    ? 'Billed monthly'
                                    : 'Billed annually',
                                style: averaText(context).caption,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatSubscriptionAmount(
                            amountMinor: amount,
                            currency: _billingPlan!.currency,
                          ),
                          style: averaText(context).sectionTitle,
                        ),
                      ],
                    ),
                  ),
                if (!_loadingPlan &&
                    _planError == null &&
                    !checkoutConfigured) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_billingPlan?.name ?? widget.application.subscriptionPlan} ${_billingCycle.apiValue} billing is not available for online payment.',
                    textAlign: TextAlign.center,
                    style: averaText(context).caption,
                  ),
                ],
                const SizedBox(height: AveraSpacing.sectionGap),
              ],
              if (_verification != null)
                AveraSurfaceCard(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                  child: Text(
                    subscriptionPaymentVerificationMessage(_verification!),
                    style: averaText(context).sectionTitle,
                  ),
                ),
              if (_error != null) ...[
                AveraSurfaceCard(
                  outlined: true,
                  child: Text(
                    _error!,
                    style: averaText(context).listItemSubtitle,
                  ),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
              ],
              if (!verified && _paymentReference == null)
                AveraPrimaryActionButton(
                  key: const Key('registration-continue-to-paystack'),
                  label: 'Continue to Paystack',
                  icon: Icons.lock_outline_rounded,
                  loading: _working,
                  onPressed: checkoutConfigured ? _startCheckout : null,
                ),
              if (!verified && _paymentReference != null) ...[
                AveraPrimaryActionButton(
                  key: const Key('registration-check-payment'),
                  label: 'Check Payment Status',
                  icon: Icons.verified_outlined,
                  loading: _working,
                  onPressed: _verifyPayment,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('registration-retry-payment'),
                  onPressed: _working
                      ? null
                      : () => _startCheckout(retry: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry Payment'),
                ),
              ],
              if (verified) ...[
                const SizedBox(height: AveraSpacing.cardGap),
                FilledButton(
                  onPressed: () => context.go(
                    Uri(
                      path: '/login',
                      queryParameters: {
                        'clinicName': widget.application.clinicName.trim(),
                      },
                    ).toString(),
                  ),
                  child: const Text('Go to Sign In'),
                ),
              ],
              const SizedBox(height: 14),
              if (!verified)
                Text(
                  'A verified payment automatically approves the clinic and sends the administrator activation email.',
                  style: averaText(context).caption,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: averaText(context).caption),
      const SizedBox(height: 3),
      Text(value, style: averaText(context).listItemTitle),
    ],
  );
}

String _paymentError(ApiException error) => switch (error.code) {
  'payment_pending' =>
    'Payment is still pending. Complete Paystack checkout, then try again.',
  'payment_in_progress' =>
    'A checkout is already in progress. Complete it or use Retry Payment.',
  'payment_not_successful' => 'Paystack did not confirm a successful payment.',
  'registration_payment_access_denied' =>
    'This payment session has expired. Your clinic application remains submitted.',
  _ => error.message,
};

const _unexpectedPaymentError =
    'The payment step could not be completed right now. Your clinic application remains submitted.';

class ClinicRegistrationPaymentCallbackScreen extends ConsumerStatefulWidget {
  const ClinicRegistrationPaymentCallbackScreen({
    super.key,
    required this.reference,
  });

  final String? reference;

  @override
  ConsumerState<ClinicRegistrationPaymentCallbackScreen> createState() =>
      _ClinicRegistrationPaymentCallbackScreenState();
}

class _ClinicRegistrationPaymentCallbackScreenState
    extends ConsumerState<ClinicRegistrationPaymentCallbackScreen> {
  SubscriptionPaymentVerification? _verification;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  Future<void> _verify() async {
    final reference = widget.reference?.trim();
    if (reference == null || reference.isEmpty) {
      setState(() => _error = 'The payment reference is missing.');
      return;
    }
    setState(() => _error = null);
    try {
      final session = await ref
          .read(registrationPaymentSessionStoreProvider)
          .loadForReference(reference);
      if (session == null) {
        throw const ApiException(
          'registration_payment_session_missing',
          'This payment session is unavailable. Your clinic application remains submitted.',
        );
      }
      final verification = await ref
          .read(subscriptionPaymentGatewayProvider)
          .verifyRegistrationPayment(
            applicationId: session.applicationId,
            accessToken: session.accessToken,
            reference: reference,
          );
      if (!verification.verified) {
        throw const ApiException(
          'payment_pending',
          'Paystack has not confirmed this payment yet.',
        );
      }
      await ref.read(registrationPaymentSessionStoreProvider).clear();
      await ref.read(clinicRegistrationDraftStoreProvider).clear();
      if (mounted) setState(() => _verification = verification);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _paymentError(error));
    } catch (_) {
      if (mounted) setState(() => _error = _unexpectedPaymentError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _verification?.verified ?? false;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirming Payment')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  confirmed
                      ? Icons.check_circle_rounded
                      : _error != null
                      ? Icons.error_outline_rounded
                      : Icons.sync_rounded,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  confirmed
                      ? subscriptionPaymentVerificationMessage(_verification!)
                      : _error ?? 'Confirming payment securely...',
                  textAlign: TextAlign.center,
                  style: averaText(context).sectionTitle,
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  FilledButton.icon(
                    onPressed: _verify,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  )
                else if (confirmed)
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Go to Sign In'),
                  )
                else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
