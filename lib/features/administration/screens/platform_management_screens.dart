import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/platform_support_session.dart';
import '../../../core/remote/api_client.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/repositories/platform_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';

class PlatformClinicsScreen extends ConsumerStatefulWidget {
  const PlatformClinicsScreen({super.key, this.status});

  final String? status;

  @override
  ConsumerState<PlatformClinicsScreen> createState() =>
      _PlatformClinicsScreenState();
}

class _PlatformClinicsScreenState extends ConsumerState<PlatformClinicsScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = (status: widget.status, search: _search);
    final clinics = ref.watch(platformClinicSearchProvider(request));
    final offline = ref.watch(platformDataOfflineProvider);
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.status == null
                ? 'Clinic Management'
                : '${widget.status} Clinics',
          ),
        ),
        body: clinics.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _PlatformLoadError(
            message: error is ApiException
                ? error.message
                : 'Clinic data could not be loaded.',
            onRetry: () =>
                ref.invalidate(platformClinicSearchProvider(request)),
          ),
          data: (items) {
            return Column(
              children: [
                if (offline)
                  const MaterialBanner(
                    content: Text(
                      'Offline: showing the latest clinics cached on this device.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) =>
                        setState(() => _search = value.trim()),
                    decoration: InputDecoration(
                      hintText:
                          'Search clinic, Account Email, reference or city',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${items.length} clinic${items.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const _EmptyState(
                          icon: Icons.business_outlined,
                          message: 'No clinics match this search and filter.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(
                              platformClinicSearchProvider(request),
                            );
                            await ref.read(
                              platformClinicSearchProvider(request).future,
                            );
                          },
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(20),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final clinic = items[index];
                              final initial = clinic.clinicName.trim().isEmpty
                                  ? '?'
                                  : clinic.clinicName
                                        .trim()
                                        .substring(0, 1)
                                        .toUpperCase();
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(child: Text(initial)),
                                title: Text(clinic.clinicName),
                                subtitle: Text(
                                  '${clinic.subscriptionPlan} • ${clinic.clinicStatus}\n${clinic.city ?? 'Location not recorded'}${clinic.email == null ? '' : '\n${clinic.email}'}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => context.push(
                                  '/platform/clinics/${clinic.clinicId}',
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PlatformClinicDetailScreen extends ConsumerWidget {
  const PlatformClinicDetailScreen({super.key, required this.clinicId});
  final String clinicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final supportSession = ref.watch(platformSupportSessionProvider);
    final activation = ref.watch(
      platformAdministratorActivationProvider(clinicId),
    );
    final applicationPayment = ref.watch(
      platformClinicApplicationPaymentProvider(clinicId),
    );
    final clinic = ref.watch(platformClinicProvider(clinicId));
    return _PlatformGuard(
      child: clinic.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: const Text('Clinic Details')),
          body: _PlatformLoadError(
            message: _platformErrorMessage(error),
            onRetry: () => ref.invalidate(platformClinicProvider(clinicId)),
          ),
        ),
        data: (clinic) {
          if (clinic == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Clinic Details')),
              body: const _EmptyState(
                icon: Icons.business_outlined,
                message: 'This clinic registration is no longer available.',
              ),
            );
          }
          final payment = applicationPayment.valueOrNull;
          final paymentVerified =
              payment != null &&
              {
                'paid',
                'testverified',
              }.contains(payment.paymentStatus.toLowerCase()) &&
              payment.transactionStatus?.toLowerCase() == 'successful';
          return Scaffold(
            appBar: AppBar(title: const Text('Clinic Details')),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (supportSession?.clinicId == clinic.clinicId)
                  Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.support_agent_rounded),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Platform Support Mode is active. Actions are recorded and no clinic user is being impersonated.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Text(
                  clinic.clinicName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${clinic.city ?? 'Location not recorded'} • ${clinic.email ?? 'No email'}',
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      _DetailRow('Status', clinic.clinicStatus),
                      _DetailRow('Subscription', clinic.subscriptionPlan),
                      _DetailRow(
                        'Registered',
                        clinic.dateRegistered
                            .toLocal()
                            .toString()
                            .split(' ')
                            .first,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                applicationPayment.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: LinearProgressIndicator(),
                    ),
                  ),
                  error: (_, __) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Payment status unavailable'),
                      subtitle: const Text(
                        'The clinic application is unchanged. Try loading its payment status again.',
                      ),
                      trailing: IconButton(
                        tooltip: 'Retry payment status',
                        onPressed: () => ref.invalidate(
                          platformClinicApplicationPaymentProvider(clinicId),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                  ),
                  data: (payment) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Registration & Payment',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (payment == null)
                            const Text(
                              'No clinic-registration application is linked to this clinic.',
                            )
                          else ...[
                            Text(
                              'Application reference',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 4),
                            SelectableText(payment.applicationReference),
                            const SizedBox(height: 12),
                            Text(
                              'Payment status',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _paymentStatusLabel(payment.paymentStatus),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _paymentStatusDescription(payment.paymentStatus),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (payment.accountEmail != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Canonical Account Email',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(payment.accountEmail!),
                            ],
                            if (payment.administratorName != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Clinic Administrator',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(payment.administratorName!),
                            ],
                            if (payment.amountMinor != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Verified transaction',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${payment.currency ?? 'NGN'} ${(payment.amountMinor! / 100).toStringAsFixed(2)}'
                                '${payment.billingCycle == null ? '' : ' • ${payment.billingCycle}'}',
                              ),
                            ],
                            if (payment.requiresIdentityReview) ...[
                              const SizedBox(height: 12),
                              const _PlatformAttentionMessage(
                                message:
                                    'Payment is verified, but the Account Email changed after Paystack checkout. Review the registration identity before administrator activation.',
                              ),
                            ],
                            if (!paymentVerified && session != null) ...[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _reconcilePayment(context, ref, session),
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text('Reconcile Paystack'),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                activation.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: LinearProgressIndicator(),
                    ),
                  ),
                  error: (_, __) => const Card(
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded),
                      title: Text('Administrator activation unavailable'),
                      subtitle: Text('Pull to refresh or try again shortly.'),
                    ),
                  ),
                  data: (value) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clinic Administrator Activation',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(_activationStatusText(value)),
                          if (value.email != null) ...[
                            const SizedBox(height: 4),
                            Text(value.email!),
                          ],
                          if (value.expiresAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Link expires ${_formatPlatformDateTime(value.expiresAt!)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (value.reason != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              value.reason!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          if (value.canResend &&
                              session != null &&
                              clinic.clinicStatus == 'Active') ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => value.status == 'NotProvisioned'
                                  ? _repairActivation(context, ref, session)
                                  : _resendActivation(context, ref, session),
                              icon: const Icon(
                                Icons.mark_email_unread_outlined,
                              ),
                              label: Text(
                                value.status == 'NotProvisioned'
                                    ? 'Repair & Send Activation'
                                    : 'Resend Activation',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          session == null ||
                              (!paymentVerified &&
                                  clinic.clinicStatus != 'Active')
                          ? null
                          : () => _setStatus(context, ref, session, 'Active'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Approve / Reactivate'),
                    ),
                    OutlinedButton.icon(
                      onPressed: session == null
                          ? null
                          : () =>
                                _setStatus(context, ref, session, 'Suspended'),
                      icon: const Icon(Icons.block_outlined),
                      label: const Text('Suspend'),
                    ),
                    OutlinedButton.icon(
                      onPressed: session == null
                          ? null
                          : () => _setStatus(context, ref, session, 'Pending'),
                      icon: const Icon(Icons.mark_email_unread_outlined),
                      label: const Text('Request Information'),
                    ),
                    if (session != null &&
                        session.canManagePlatform(
                          Permissions.platformSupportAccess,
                        ))
                      OutlinedButton.icon(
                        onPressed: () =>
                            _toggleSupportMode(context, ref, session, clinic),
                        icon: Icon(
                          supportSession?.clinicId == clinic.clinicId
                              ? Icons.logout_rounded
                              : Icons.support_agent_rounded,
                        ),
                        label: Text(
                          supportSession?.clinicId == clinic.clinicId
                              ? 'Exit Support Mode'
                              : 'Open Support Mode',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Support access is intentionally read-only and requires a server-side support session in production.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (session?.isPlatformOwner == true) ...[
                  const SizedBox(height: 28),
                  Text(
                    'Danger Zone',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mutual deletion sends a six-digit confirmation code to the clinic Account Email. Nothing is deleted until that code is confirmed.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _requestDeletion(
                              context,
                              ref,
                              session!,
                              clinic,
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Request Mutual Deletion'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleSupportMode(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    Clinic clinic,
  ) async {
    final active = ref.read(platformSupportSessionProvider);
    final starting = active?.clinicId != clinic.clinicId;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordPlatformSupportAccess(
            actingSession: session,
            clinicId: clinic.clinicId,
            started: starting,
          );
      ref.read(platformSupportSessionProvider.notifier).state = starting
          ? PlatformSupportSession(
              clinicId: clinic.clinicId,
              clinicName: clinic.clinicName,
              startedAt: DateTime.now(),
              startedBy: session.user.userId,
            )
          : null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              starting
                  ? 'Platform Support Mode opened for ${clinic.clinicName}.'
                  : 'Platform Support Mode closed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    String status,
  ) async {
    try {
      PlatformAdministratorActivation? activation;
      if (status == 'Active') {
        final result = await ref
            .read(platformRepositoryProvider)
            .approveClinic(session: session, clinicId: clinicId);
        activation = result.activation;
      } else {
        await ref
            .read(platformRepositoryProvider)
            .updateClinicStatus(
              session: session,
              clinicId: clinicId,
              status: status,
            );
      }
      _invalidateClinicState(ref);
      if (context.mounted) {
        if (activation?.activationUrl != null) {
          await _showOneTimeActivationLink(context, activation!);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (activation?.deliveryMethod) {
              'email_submitted' || 'email' =>
                'Clinic activated. The administrator was provisioned and the activation email was submitted to the email provider${activation?.email == null ? '' : ' for ${activation!.email}'}.',
              'email_failed' =>
                'Clinic activated and the administrator was provisioned, but the activation email could not be submitted. Use Resend Activation to try again.',
              _ when activation?.status == 'Active' =>
                'Clinic is active and administrator access is already configured.',
              _ => 'Clinic status changed to $status.',
            }),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }

  Future<void> _resendActivation(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      final activation = await ref
          .read(platformRepositoryProvider)
          .resendAdministratorActivation(session: session, clinicId: clinicId);
      _invalidateClinicState(ref);
      if (context.mounted) {
        if (activation.activationUrl != null) {
          await _showOneTimeActivationLink(context, activation);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _emailWasSubmitted(activation)
                  ? 'The Clinic Administrator was reconciled and a new activation email was submitted to the email provider${activation.email == null ? '' : ' for ${activation.email}'}. '
                  : activation.deliveryMethod == 'email_failed'
                  ? 'Administrator provisioning is complete, but activation email submission failed. Check the email configuration and try again.'
                  : 'Administrator provisioning is complete, but manual activation delivery is required.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }

  Future<void> _repairActivation(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      final activation = await ref
          .read(platformRepositoryProvider)
          .repairAdministratorActivation(session: session, clinicId: clinicId);
      _invalidateClinicState(ref);
      if (!context.mounted) return;
      if (activation.activationUrl != null) {
        await _showOneTimeActivationLink(context, activation);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _emailWasSubmitted(activation)
                ? 'Administrator access was repaired and the activation email was submitted to the email provider${activation.email == null ? '' : ' for ${activation.email}'}. '
                : activation.deliveryMethod == 'email_failed'
                ? 'Administrator access was repaired, but email submission failed. Try Resend Activation after checking the email configuration.'
                : 'Administrator access was repaired, but manual activation delivery is required.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }

  Future<void> _reconcilePayment(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
  ) async {
    try {
      final result = await ref
          .read(platformRepositoryProvider)
          .reconcileClinicPayment(session: session, clinicId: clinicId);
      _invalidateClinicState(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.applicationApproved
                ? 'Paystack payment was verified and the clinic was activated.'
                : result.verified
                ? result.message ??
                      'Paystack payment was verified. Review the administrator state before activation.'
                : 'Paystack has not verified this payment.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }

  Future<void> _requestDeletion(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    Clinic clinic,
  ) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Mutual Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A confirmation code will be sent to ${clinic.clinicName}\'s canonical Account Email. The clinic must provide that code before deletion can continue.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Why both parties agreed to delete this clinic',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.length >= 3) Navigator.pop(dialogContext, value);
            },
            icon: const Icon(Icons.mark_email_unread_outlined),
            label: const Text('Email Code'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return;

    try {
      final challenge = await ref
          .read(platformRepositoryProvider)
          .requestClinicDeletion(
            session: session,
            clinicId: clinicId,
            reason: reason,
          );
      if (!context.mounted) return;
      final codeController = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm Mutual Deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The confirmation code was submitted to the email provider for ${challenge.recipientEmail}. Enter the six-digit code below. It expires ${_formatPlatformDateTime(challenge.expiresAt)}.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                autofocus: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Deletion code'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirmation revokes clinic access and releases its Account Email for a new registration. Payment and audit history remain preserved.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final value = codeController.text.trim();
                if (value.length == 6) Navigator.pop(dialogContext, value);
              },
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Confirm Deletion'),
            ),
          ],
        ),
      );
      codeController.dispose();
      if (code == null || !context.mounted) return;
      await ref
          .read(platformRepositoryProvider)
          .confirmClinicDeletion(
            session: session,
            clinicId: clinicId,
            requestId: challenge.requestId,
            code: code,
          );
      _invalidateClinicState(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Clinic mutually deleted. Its Account Email can now register again.',
            ),
          ),
        );
        context.go('/platform/clinics');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }

  void _invalidateClinicState(WidgetRef ref) {
    ref.invalidate(platformClinicProvider(clinicId));
    ref.invalidate(platformClinicApplicationPaymentProvider(clinicId));
    ref.invalidate(platformAdministratorActivationProvider(clinicId));
    ref.invalidate(platformClinicsProvider);
    ref.invalidate(platformClinicSearchProvider);
    ref.invalidate(platformOverviewProvider);
  }

  String _activationStatusText(PlatformAdministratorActivation activation) {
    return switch (activation.status) {
      'Active' => 'Activated',
      'PendingActivation' =>
        _emailWasSubmitted(activation)
            ? 'Pending activation - submitted to email provider'
            : activation.deliveryMethod == 'email_failed'
            ? 'Pending activation - email submission failed'
            : 'Pending activation - manual delivery required',
      'DeliveryFailed' => 'Pending activation - email submission failed',
      'LinkExpired' => 'Activation link expired',
      'LinkRevoked' => 'Activation link revoked',
      'NotProvisioned' =>
        activation.canResend
            ? 'Administrator not provisioned - use Resend Activation to repair access'
            : 'Administrator not provisioned - registration Account Email or administrator details are missing',
      'LocalDevelopment' => 'Local development activation',
      _ => activation.status,
    };
  }

  String _paymentStatusLabel(String status) {
    return switch (status.toLowerCase()) {
      'paid' => 'Paid',
      'testverified' => 'Test payment verified',
      'failed' => 'Payment failed',
      'cancelled' || 'canceled' => 'Payment cancelled',
      _ => 'Pending payment',
    };
  }

  String _paymentStatusDescription(String status) {
    return switch (status.toLowerCase()) {
      'paid' =>
        'Payment is verified. Platform Owner approval and administrator activation remain separate required steps.',
      'testverified' =>
        'Payment was verified through Paystack test mode. The clinic and administrator activation statuses are shown separately above.',
      'failed' || 'cancelled' || 'canceled' =>
        'The clinic application remains submitted and payment may be retried safely.',
      _ =>
        'Payment has not been verified. The clinic application remains pending review.',
    };
  }

  Future<void> _showOneTimeActivationLink(
    BuildContext context,
    PlatformAdministratorActivation activation,
  ) async {
    final link = activation.activationUrl!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Temporary activation-link delivery'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Email delivery is not configured. This secure, single-use link is shown only now. Deliver it privately to the clinic applicant.',
              ),
              const SizedBox(height: 12),
              SelectableText(link),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Activation link copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy activation link'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

String _platformErrorMessage(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'clinic_deletion_email_unavailable' =>
        'Deletion confirmation email is not configured. Nothing was deleted.',
      'clinic_deletion_email_failed' =>
        'Deletion confirmation email could not be submitted. Nothing was deleted.',
      'clinic_deletion_code_invalid' => error.message,
      'clinic_deletion_code_expired' =>
        'The confirmation code has expired. Request a new code.',
      'clinic_deletion_attempts_exhausted' =>
        'Too many incorrect attempts. Request a new code.',
      'clinic_deletion_request_unavailable' =>
        'This deletion request is no longer available. Request a new code.',
      'clinic_deletion_request_failed' ||
      'clinic_deletion_confirmation_failed' ||
      'internal_error' => 'Deletion service is temporarily unavailable.',
      'platform_owner_self_lockout' =>
        'You cannot suspend or deactivate your own Platform Owner account.',
      'platform_owner_last_active' =>
        'At least one active Platform Owner account must remain.',
      'forbidden' => 'Only a Platform Owner can manage platform accounts.',
      _ => error.message,
    };
  }
  return 'The Platform Owner action could not be completed. Please try again.';
}

bool _emailWasSubmitted(PlatformAdministratorActivation activation) =>
    activation.deliveryMethod == 'email_submitted' ||
    activation.deliveryMethod == 'email';

String _formatPlatformDateTime(DateTime value) =>
    DateFormat('d MMM y, h:mm a').format(value.toLocal());

class PlatformSubscriptionsScreen extends ConsumerStatefulWidget {
  const PlatformSubscriptionsScreen({super.key, this.status});
  final String? status;

  @override
  ConsumerState<PlatformSubscriptionsScreen> createState() =>
      _PlatformSubscriptionsScreenState();
}

class _PlatformSubscriptionsScreenState
    extends ConsumerState<PlatformSubscriptionsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  int _page = 1;
  static const _pageSize = 25;

  ({String? status, String search, int page, int pageSize}) get _request => (
    status: widget.status,
    search: _search,
    page: _page,
    pageSize: _pageSize,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final snapshot = ref.watch(platformSubscriptionsProvider(_request));
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Subscriptions & Plans',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: snapshot.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _PlatformLoadError(
            message: 'Subscription data is unavailable: $error',
            onRetry: () =>
                ref.invalidate(platformSubscriptionsProvider(_request)),
          ),
          data: (data) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SearchBar(
                  controller: _searchController,
                  hintText: 'Search clinic or account email',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_search.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                            _page = 1;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                  ],
                  onSubmitted: (value) => setState(() {
                    _search = value.trim();
                    _page = 1;
                  }),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Active ${data.active}')),
                    Chip(label: Text('Expiring ${data.expiring}')),
                    Chip(label: Text('Expired ${data.expired}')),
                    Chip(label: Text('Payment issues ${data.paymentIssues}')),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.status == null
                      ? 'Subscriptions (${data.total})'
                      : '${widget.status} subscriptions (${data.total})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (data.items.isEmpty)
                  const _EmptyState(
                    icon: Icons.workspace_premium_outlined,
                    message: 'No subscription records match this filter.',
                  )
                else
                  ...data.items.map(
                    (item) => ListTile(
                      title: Text(item.clinicName),
                      subtitle: Text(
                        '${item.plan} • ${item.status} • ${item.billingCycle}',
                      ),
                      trailing: session == null
                          ? null
                          : PopupMenuButton<String>(
                              tooltip: 'Change subscription',
                              onSelected: (plan) => _changePlan(
                                context,
                                ref,
                                session,
                                item.clinicId,
                                plan,
                              ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'Starter',
                                  child: Text('Starter'),
                                ),
                                PopupMenuItem(
                                  value: 'Professional',
                                  child: Text('Professional'),
                                ),
                                PopupMenuItem(
                                  value: 'Enterprise',
                                  child: Text('Enterprise'),
                                ),
                              ],
                            ),
                    ),
                  ),
                if (data.total > data.pageSize) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: data.page > 1
                            ? () => setState(() => _page--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('Page ${data.page}'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: data.hasNextPage
                            ? () => setState(() => _page++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 32),
                Text(
                  'Recent payments',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...data.payments
                    .take(20)
                    .map(
                      (payment) => ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(payment.clinicName),
                        subtitle: Text(
                          '${payment.reference} • ${payment.status}',
                        ),
                        trailing: Text(
                          '${payment.mode.toLowerCase() == 'live'
                              ? 'LIVE'
                              : payment.mode.toLowerCase() == 'test'
                              ? 'TEST'
                              : 'UNKNOWN'}\n${payment.currency} ${(payment.amountMinor / 100).toStringAsFixed(0)}',
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _changePlan(
    BuildContext context,
    WidgetRef ref,
    UserSession session,
    String clinicId,
    String plan,
  ) async {
    try {
      await ref
          .read(platformRepositoryProvider)
          .updateClinicSubscription(
            session: session,
            clinicId: clinicId,
            plan: plan,
          );
      ref.invalidate(platformClinicsProvider);
      ref.invalidate(platformOverviewProvider);
      ref.invalidate(platformSubscriptionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription changed to $plan.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class PlatformUsersScreen extends ConsumerWidget {
  const PlatformUsersScreen({super.key, this.status});
  final String? status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    return _PlatformGuard(
      child: Scaffold(
        appBar: AppBar(title: const Text('Platform Users')),
        body: ref
            .watch(platformUsersProvider(status))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _PlatformLoadError(
                message: 'Platform users are unavailable: $error',
                onRetry: () => ref.invalidate(platformUsersProvider(status)),
              ),
              data: (page) => page.items.isEmpty
                  ? const _EmptyState(
                      icon: Icons.people_outline,
                      message: 'No platform accounts found.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = page.items[index];
                        final canManage =
                            session?.user.accountType == 'PlatformOwner' &&
                            session?.user.userId != user.userId;
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              user.fullName.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(user.fullName),
                          subtitle: Text(
                            '${user.accountType} • ${user.status}\n${user.email}',
                          ),
                          isThreeLine: true,
                          trailing: canManage
                              ? PopupMenuButton<String>(
                                  tooltip: 'Manage account status',
                                  onSelected: (status) =>
                                      _updateStatus(context, ref, user, status),
                                  itemBuilder: (_) => [
                                    if (user.status != 'Active')
                                      const PopupMenuItem(
                                        value: 'Active',
                                        child: Text('Reactivate'),
                                      ),
                                    if (user.status == 'Active')
                                      const PopupMenuItem(
                                        value: 'Suspended',
                                        child: Text('Suspend'),
                                      ),
                                    if (user.status != 'Deactivated')
                                      const PopupMenuItem(
                                        value: 'Deactivated',
                                        child: Text('Deactivate'),
                                      ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
      ),
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    PlatformUserRecord user,
    String status,
  ) async {
    final action = status == 'Active'
        ? 'reactivate'
        : status == 'Suspended'
        ? 'suspend'
        : 'deactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} account?',
        ),
        content: Text(
          "This will change ${user.fullName}'s platform access to $status.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action[0].toUpperCase() + action.substring(1)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    try {
      await ref
          .read(platformRepositoryProvider)
          .updatePlatformUserStatus(
            session: session,
            userId: user.userId,
            status: status,
            reason: 'Platform Owner account management',
          );
      ref.invalidate(platformUsersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.fullName} is now $status.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_platformErrorMessage(error))));
      }
    }
  }
}

class PlatformAuditLogsScreen extends ConsumerWidget {
  const PlatformAuditLogsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Global Audit Logs')),
      body: ref
          .watch(platformAuditProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _PlatformLoadError(
              message: 'Audit data is unavailable: $error',
              onRetry: () => ref.invalidate(platformAuditProvider),
            ),
            data: (page) => page.items.isEmpty
                ? const _EmptyState(
                    icon: Icons.history_outlined,
                    message: 'No administrative activity recorded yet.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: page.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = page.items[index];
                      return ListTile(
                        leading: Icon(
                          log.success
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                        ),
                        title: Text(log.action),
                        subtitle: Text(
                          '${log.targetType} • ${log.actorName ?? 'System'}\n${log.createdAt.toLocal()}',
                        ),
                        isThreeLine: true,
                        onTap: () => _showAuditDetails(context, log),
                      );
                    },
                  ),
          ),
    ),
  );
}

void _showAuditDetails(BuildContext context, PlatformAuditRecord log) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Audit details'),
      content: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AuditDetail(label: 'Action', value: log.action),
              _AuditDetail(
                label: 'Date',
                value: _formatPlatformDateTime(log.createdAt),
              ),
              _AuditDetail(label: 'Actor', value: log.actorName ?? 'System'),
              _AuditDetail(
                label: 'Target',
                value:
                    '${log.targetType}${log.targetId == null ? '' : ' • ${log.targetId}'}',
              ),
              _AuditDetail(
                label: 'Clinic',
                value: log.clinicName ?? 'Platform',
              ),
              _AuditDetail(
                label: 'Result',
                value: log.success ? 'Successful' : 'Failed',
              ),
              if (log.reason?.trim().isNotEmpty == true)
                _AuditDetail(label: 'Reason', value: log.reason!),
              _AuditDetail(
                label: 'Previous',
                value: _safeAuditSummary(log.previousSummary),
              ),
              _AuditDetail(
                label: 'New',
                value: _safeAuditSummary(log.newSummary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

String _safeAuditSummary(Map<String, dynamic>? summary) {
  if (summary == null || summary.isEmpty) return 'Not recorded';
  dynamic redact(dynamic value) {
    if (value is Map) {
      return value.map((key, nested) {
        final normalized = key.toString().toLowerCase();
        final sensitive = const [
          'password',
          'secret',
          'token',
          'authorization',
          'api_key',
        ].any(normalized.contains);
        return MapEntry(
          key.toString(),
          sensitive ? '[redacted]' : redact(nested),
        );
      });
    }
    if (value is Iterable) return value.map(redact).toList(growable: false);
    return value;
  }

  return const JsonEncoder.withIndent('  ').convert(redact(summary));
}

class _AuditDetail extends StatelessWidget {
  const _AuditDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Text(value),
      ],
    ),
  );
}

class PlatformOperationsScreen extends StatelessWidget {
  const PlatformOperationsScreen({super.key});

  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Operations')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.pageTopPadding,
          AveraSpacing.pageHorizontalPadding,
          AveraSpacing.bottomContentClearance,
        ),
        children: [
          _PlatformRouteCard(
            icon: Icons.business_center_outlined,
            title: 'Clinics',
            subtitle: 'Review, approve, suspend, and support clinics',
            route: '/platform/clinics',
          ),
          _PlatformRouteCard(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscriptions',
            subtitle: 'Manage plans, billing status, payments, and renewals',
            route: '/platform/subscriptions',
          ),
          _PlatformRouteCard(
            icon: Icons.campaign_outlined,
            title: 'Announcements',
            subtitle:
                'Platform notices are not configured for this environment',
            route: '/platform/announcements',
          ),
          _PlatformRouteCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Platform Administrators',
            subtitle: 'Manage appointed platform accounts',
            route: '/platform/users',
          ),
          if (BackendConfiguration.isLocalMode && kDebugMode)
            _PlatformRouteCard(
              icon: Icons.science_outlined,
              title: 'Developer Settings',
              subtitle: 'Local development and feature-gate tools',
              route: '/platform/developer-settings',
            ),
          _PlatformRouteCard(
            icon: Icons.policy_outlined,
            title: 'Audit & Security',
            subtitle: 'Review immutable platform audit logs',
            route: '/platform/audit',
          ),
          _PlatformRouteCard(
            icon: Icons.settings_outlined,
            title: 'Platform Settings',
            subtitle: 'Security, integrations, email, and configuration',
            route: '/platform/settings',
          ),
        ],
      ),
    ),
  );
}

class PlatformNotificationsScreen extends ConsumerWidget {
  const PlatformNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Notifications')),
      body: ref
          .watch(platformNotificationsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _PlatformLoadError(
              message: 'Notifications are unavailable: $error',
              onRetry: () => ref.invalidate(platformNotificationsProvider),
            ),
            data: (snapshot) => snapshot.items.isEmpty
                ? const _EmptyState(
                    icon: Icons.notifications_none_rounded,
                    message: 'No platform notifications require attention.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: snapshot.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = snapshot.items[index];
                      return ListTile(
                        leading: Icon(
                          item.severity == 'error'
                              ? Icons.error_outline
                              : Icons.warning_amber_outlined,
                        ),
                        title: Text(item.title),
                        subtitle: Text(
                          '${item.message}\n${item.createdAt.toLocal()}',
                        ),
                        isThreeLine: true,
                        onTap: () => context.go(item.route),
                      );
                    },
                  ),
          ),
    ),
  );
}

class PlatformOperationsStatusScreen extends ConsumerWidget {
  const PlatformOperationsStatusScreen({super.key, this.focus});

  final String? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ref
          .watch(platformOperationsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _PlatformLoadError(
              message: 'Operational status is unavailable: $error',
              onRetry: () => ref.invalidate(platformOperationsProvider),
            ),
            data: (status) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (status.isUnavailable)
                  const _PlatformAttentionMessage(
                    message:
                        'Local development does not provide backend health data.',
                  ),
                if (focus == null || focus == 'system')
                  _PlatformStatusTile(
                    icon: Icons.monitor_heart_outlined,
                    title: 'System health',
                    value: status.systemStatus,
                    detail: 'Database: ${status.databaseStatus}',
                  ),
                if (focus == null || focus == 'email')
                  _PlatformStatusTile(
                    icon: Icons.email_outlined,
                    title: 'Email delivery',
                    value: status.emailStatus,
                    detail:
                        'Provider: ${status.emailProvider}${status.lastAttemptAt == null ? '' : '\nLast attempt: ${status.lastAttemptAt!.toLocal()}'}',
                  ),
                if (focus == null || focus == 'storage')
                  _PlatformStatusTile(
                    icon: Icons.storage_outlined,
                    title: 'Storage',
                    value: status.storageStatus,
                    detail:
                        'Provider: ${status.storageProvider}\nObject count: ${status.objectCount?.toString() ?? 'Unavailable'}\nBytes: Unavailable',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Operational data is read from the AVERA backend. Secret keys and credentials are never shown here.',
                ),
              ],
            ),
          ),
    ),
  );

  String get _title => switch (focus) {
    'email' => 'Email Delivery',
    'storage' => 'Storage Usage',
    _ => 'System Health',
  };
}

class PlatformSettingsScreen extends ConsumerWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Settings')),
      body: ref
          .watch(platformOperationsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _PlatformLoadError(
              message: 'Platform configuration is unavailable: $error',
              onRetry: () => ref.invalidate(platformOperationsProvider),
            ),
            data: (status) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _PlatformStatusTile(
                  icon: Icons.email_outlined,
                  title: 'Email provider',
                  value: status.emailProvider,
                  detail: status.emailStatus,
                ),
                _PlatformStatusTile(
                  icon: Icons.cloud_outlined,
                  title: 'Storage provider',
                  value: status.storageProvider,
                  detail: status.storageStatus,
                ),
                _PlatformStatusTile(
                  icon: Icons.payments_outlined,
                  title: 'Payment provider',
                  value: status.paymentProvider,
                  detail:
                      '${status.paymentStatus}\nMode: ${status.paymentMode.toUpperCase()}',
                ),
                _PlatformStatusTile(
                  icon: Icons.security_outlined,
                  title: 'Security',
                  value: 'Protected',
                  detail:
                      'Platform Owner authorization and audit logging are enabled.',
                ),
              ],
            ),
          ),
    ),
  );
}

class PlatformAnnouncementsScreen extends StatelessWidget {
  const PlatformAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: const _EmptyState(
        icon: Icons.campaign_outlined,
        message:
            'Announcements are not available until platform notice storage is configured.',
      ),
    ),
  );
}

class _PlatformStatusTile extends StatelessWidget {
  const _PlatformStatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: Text(value, textAlign: TextAlign.end),
    ),
  );
}

class PlatformAccountScreen extends ConsumerWidget {
  const PlatformAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Platform Owner Account')),
      body: ref
          .watch(userSessionProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const _EmptyState(
              icon: Icons.error_outline,
              message: 'Account information is unavailable.',
            ),
            data: (session) => ListView(
              padding: const EdgeInsets.fromLTRB(
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.pageTopPadding,
                AveraSpacing.pageHorizontalPadding,
                AveraSpacing.bottomContentClearance,
              ),
              children: [
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    session.user.fullName
                        .trim()
                        .split(RegExp(r'\s+'))
                        .take(2)
                        .map((part) => part.isEmpty ? '' : part[0])
                        .join()
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  session.user.fullName,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).extension<AveraTextStyles>()!.pageTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  'Platform Owner',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).extension<AveraTextStyles>()!.pageSubtitle,
                ),
                const SizedBox(height: 4),
                Text(
                  session.user.email,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).extension<AveraTextStyles>()!.pageSubtitle,
                ),
                const SizedBox(height: 24),
                _PlatformRouteCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  subtitle: 'Update your protected Platform Owner credentials',
                  route: '/platform/password',
                ),
                _PlatformRouteCard(
                  icon: Icons.security_outlined,
                  title: 'Security Settings',
                  subtitle: 'Review authentication and platform security',
                  route: '/platform/mfa',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _logout(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                ),
              ],
            ),
          ),
    ),
  );

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    if (BackendConfiguration.isLocalMode) {
      await ref.read(localSessionStoreProvider).clear();
    } else {
      await ref.read(authenticationRepositoryProvider).signOut();
    }
    await ref.read(biometricAuthServiceProvider).clear();
    ref.invalidate(biometricEnrollmentProvider);
    ref.invalidate(userSessionProvider);
    if (context.mounted) context.go('/login');
  }
}

class _PlatformRouteCard extends StatelessWidget {
  const _PlatformRouteCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AveraSpacing.compactRowGap),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      minVerticalPadding: 14,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(route),
    ),
  );
}

class PlatformUtilityScreen extends StatelessWidget {
  const PlatformUtilityScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _EmptyState(icon: icon, message: message),
    ),
  );
}

class PlatformPasswordScreen extends ConsumerStatefulWidget {
  const PlatformPasswordScreen({super.key});
  @override
  ConsumerState<PlatformPasswordScreen> createState() =>
      _PlatformPasswordScreenState();
}

class _PlatformPasswordScreenState
    extends ConsumerState<PlatformPasswordScreen> {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  bool saving = false;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PlatformGuard(
    child: Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: confirm,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving...' : 'Update Password'),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    if (next.text != confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new passwords do not match.')),
      );
      return;
    }
    final session = ref.read(userSessionProvider).valueOrNull;
    if (session == null) return;
    setState(() => saving = true);
    try {
      await ref
          .read(clinicRepositoryProvider)
          .changeOwnPassword(
            session: session,
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
        context.pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PlatformGuard extends ConsumerWidget {
  const _PlatformGuard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _PlatformDenied(),
      data: (value) =>
          value.isPlatformAccount ? child : const _PlatformDenied(),
    );
  }
}

class _PlatformDenied extends StatelessWidget {
  const _PlatformDenied();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.go('/login'),
        child: const Text('Return to Sign In'),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(label), trailing: Text(value));
}

class _PlatformAttentionMessage extends StatelessWidget {
  const _PlatformAttentionMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformLoadError extends StatelessWidget {
  const _PlatformLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
