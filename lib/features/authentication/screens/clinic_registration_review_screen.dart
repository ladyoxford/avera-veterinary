import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/repositories/clinic_repository.dart';
import '../../shared/widgets/avera_auth_ui.dart';
import 'clinic_registration_payment_screen.dart';

enum ClinicRegistrationReviewAction { edit }

class ClinicRegistrationReviewScreen extends StatelessWidget {
  const ClinicRegistrationReviewScreen({super.key, required this.application});

  final ClinicApplication application;

  @override
  Widget build(BuildContext context) {
    final freePlanActive = application.isFreePlanActive;
    return AveraAuthScaffold(
      backTitle: freePlanActive
          ? 'Registration Complete'
          : 'Review Your Clinic',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            freePlanActive
                ? 'Your Starter plan is active. Use the link sent to the Account Email to create the administrator password.'
                : 'Confirm these details before opening Paystack.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AveraAuthCard(
            child: Column(
              children: [
                _ReviewRow(label: 'Clinic', value: application.clinicName),
                _ReviewRow(
                  label: 'Administrator',
                  value: application.administratorName,
                ),
                _ReviewRow(
                  label: 'Account Email',
                  value: application.accountEmail,
                ),
                _ReviewRow(label: 'Phone', value: application.phoneNumber),
                _ReviewRow(
                  label: 'Address',
                  value:
                      '${application.address}, ${application.city}, ${application.country}',
                ),
                _ReviewRow(label: 'Time Zone', value: application.timeZone),
                _ReviewRow(
                  label: 'Plan',
                  value: application.subscriptionPlan,
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!freePlanActive) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('edit-registration-details'),
                onPressed: () =>
                    Navigator.pop(context, ClinicRegistrationReviewAction.edit),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Details'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: Key(
                freePlanActive
                    ? 'continue-registration-to-sign-in'
                    : 'continue-registration-to-payment',
              ),
              onPressed: freePlanActive
                  ? () => context.go(
                      Uri(
                        path: '/login',
                        queryParameters: {
                          'clinicName': application.clinicName.trim(),
                        },
                      ).toString(),
                    )
                  : application.canContinueToPayment
                  ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ClinicRegistrationPaymentScreen(
                          application: application,
                        ),
                      ),
                    )
                  : null,
              icon: Icon(
                freePlanActive
                    ? Icons.login_rounded
                    : Icons.lock_outline_rounded,
              ),
              label: Text(
                freePlanActive ? 'Go to Sign In' : 'Continue to Payment',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            freePlanActive
                ? 'No payment or Paystack checkout is required for Starter. If the activation email is delayed, AVERA support can resend it.'
                : 'Payment is verified by the AVERA backend. Closing or cancelling Paystack keeps this application available for retry.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 13),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}
