import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/remote/auth_remote_data_source.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../shared/widgets/avera_auth_ui.dart';
import 'clinic_registration_screen.dart';
import 'security_auth_screens.dart';

class ProviderLinkVerificationScreen extends ConsumerStatefulWidget {
  const ProviderLinkVerificationScreen({super.key, required this.outcome});

  final RemoteProviderAuthOutcome outcome;

  @override
  ConsumerState<ProviderLinkVerificationScreen> createState() =>
      _ProviderLinkVerificationScreenState();
}

class _ProviderLinkVerificationScreenState
    extends ConsumerState<ProviderLinkVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_working || !(_formKey.currentState?.validate() ?? false)) return;
    final challengeId = widget.outcome.challengeId;
    if (challengeId == null) return;
    final platform = Theme.of(context).platform.name;
    setState(() => _working = true);
    try {
      final deviceId = await ref
          .read(offlineAuthorizationServiceProvider)
          .deviceId();
      final result = await ref
          .read(authenticationRepositoryProvider)
          .verifyProviderLink(
            challengeId: challengeId,
            code: _code.text.trim(),
            deviceId: deviceId,
            platform: platform,
          );
      if (mounted) Navigator.pop(context, result);
    } on MfaRequiredException catch (challenge) {
      if (mounted) {
        context.go(
          '/mfa-challenge',
          extra: MfaChallengeArgs(
            challengeToken: challenge.challengeToken,
            expiresIn: challenge.expiresIn,
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.outcome.provider ?? 'provider';
    final providerName = provider[0].toUpperCase() + provider.substring(1);
    return AveraAuthScaffold(
      backTitle: 'Connect $providerName',
      showBrand: false,
      child: Form(
        key: _formKey,
        child: AveraAuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We found an existing AVERA account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A verification code was sent to ${widget.outcome.maskedEmail ?? 'your account email'}. Enter it to securely connect $providerName.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 26),
              AveraAuthField(
                key: const Key('provider-link-code'),
                label: 'Six-Digit Code',
                controller: _code,
                hintText: '000000',
                icon: Icons.verified_user_outlined,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                onFieldSubmitted: (_) => _verify(),
                validator: (value) =>
                    RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Enter the six-digit code.',
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('verify-provider-link'),
                  onPressed: _working ? null : _verify,
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: const Text('Verify & Continue'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The code expires after 10 minutes and can be used only once.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExistingAveraEmailScreen extends StatefulWidget {
  const ExistingAveraEmailScreen({super.key, required this.provider});

  final String provider;

  @override
  State<ExistingAveraEmailScreen> createState() =>
      _ExistingAveraEmailScreenState();
}

class _ExistingAveraEmailScreenState extends State<ExistingAveraEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _continue() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _email.text.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) => AveraAuthScaffold(
    backTitle: 'Find Your AVERA Account',
    showBrand: false,
    child: Form(
      key: _formKey,
      child: AveraAuthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your existing account email',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.provider} did not provide an email that AVERA can safely match. We will verify this address before linking anything.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            AveraAuthField(
              key: const Key('existing-avera-email'),
              label: 'Existing AVERA Email',
              controller: _email,
              hintText: 'you@clinic.com',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onFieldSubmitted: (_) => _continue(),
              validator: (value) =>
                  RegExp(r'^\S+@\S+\.\S+$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Enter a valid email address.',
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('continue-existing-email'),
                onPressed: _continue,
                child: const Text('Continue Securely'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProviderAuthStatusScreen extends StatelessWidget {
  const ProviderAuthStatusScreen({
    super.key,
    required this.title,
    required this.message,
    this.registrationEmail,
  });

  final String title;
  final String message;
  final String? registrationEmail;

  @override
  Widget build(BuildContext context) => AveraAuthScaffold(
    backTitle: title,
    showBrand: false,
    child: AveraAuthCard(
      child: Column(
        children: [
          Icon(
            registrationEmail == null
                ? Icons.mark_email_read_outlined
                : Icons.add_business_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: registrationEmail == null
                ? OutlinedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Return to Sign In'),
                  )
                : FilledButton.icon(
                    key: const Key('provider-register-clinic'),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ClinicRegistrationScreen(
                          initialAccountEmail: registrationEmail,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Register Your Clinic'),
                  ),
          ),
        ],
      ),
    ),
  );
}

ClinicApplication clinicApplicationFromRemote(
  RemoteRegistrationApplication application,
) => ClinicApplication(
  clinicName: application.clinicName,
  accountEmail: application.accountEmail,
  phoneNumber: application.phoneNumber,
  address: application.address,
  city: application.city,
  country: application.country,
  administratorName: application.administratorName,
  administratorPhone: application.administratorPhone,
  professionalTitle: application.professionalTitle,
  subscriptionPlan: application.selectedPlan,
  timeZone: application.timeZone,
  reference: application.reference,
  applicationId: application.applicationId,
  clinicId: application.clinicId,
  paymentStatus: application.paymentStatus,
  paymentAccessToken: application.paymentAccessToken,
  draftAccessToken: application.draftAccessToken,
  status: application.status,
);
