import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/config/backend_configuration.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../models/invoice_presentation.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_presentation_factory.dart';
import '../widgets/invoice_preview_sheet.dart';
import '../widgets/payment_capture_dialog.dart';
import 'remote_billing_history_screen.dart';

class BillingHistoryScreen extends ConsumerStatefulWidget {
  const BillingHistoryScreen({super.key, this.initialInvoiceId});

  final int? initialInvoiceId;

  @override
  ConsumerState<BillingHistoryScreen> createState() =>
      _BillingHistoryScreenState();
}

class _BillingHistoryScreenState extends ConsumerState<BillingHistoryScreen> {
  String _query = '';
  String _status = 'All';
  String _period = 'All time';
  bool _newestFirst = true;
  bool _openedInitialInvoice = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.can(Permissions.billingHistory)) {
      return const Scaffold(
        body: _BillingState(
          icon: Icons.lock_outline_rounded,
          title: 'Billing history unavailable',
          message: 'Your role does not permit access to invoice history.',
        ),
      );
    }
    if (BackendConfiguration.isConfigured) {
      return RemoteBillingHistoryScreen(session: session);
    }
    final repository = ref.read(clinicRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing History'),
        actions: [
          IconButton(
            tooltip: _newestFirst ? 'Oldest first' : 'Newest first',
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            icon: Icon(
              _newestFirst ? Icons.south_rounded : Icons.north_rounded,
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<BillingHistoryEntry>>(
        stream: repository.watchBillingHistory(session),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BillingState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load billing history',
              message: 'The invoice ledger could not be loaded.',
              action: FilledButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!.where(_matches).toList()
            ..sort(
              (a, b) => _newestFirst
                  ? b.invoice.createdAt.compareTo(a.invoice.createdAt)
                  : a.invoice.createdAt.compareTo(b.invoice.createdAt),
            );
          _openInitialInvoice(entries, session);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.pageTopPadding,
              AveraSpacing.pageHorizontalPadding,
              AveraSpacing.bottomContentClearance,
            ),
            children: [
              Text(
                'Invoices, payments, refunds, and outstanding balances.',
                style: averaText(context).pageSubtitle,
              ),
              const SizedBox(height: AveraSpacing.subtitleToContentGap),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText:
                      'Search invoice, patient, owner, or hospital number',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: AveraSpacing.compactRowGap),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final status in const [
                      'All',
                      'Draft',
                      'Unpaid',
                      'Partially paid',
                      'Paid',
                      'Refunded',
                      'Voided',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(status),
                          selected: _status == status,
                          onSelected: (_) => setState(() => _status = status),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AveraSpacing.compactRowGap),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '30 days', label: Text('30 days')),
                  ButtonSegment(value: 'This year', label: Text('This year')),
                  ButtonSegment(value: 'All time', label: Text('All time')),
                ],
                selected: {_period},
                onSelectionChanged: (value) =>
                    setState(() => _period = value.first),
              ),
              const SizedBox(height: AveraSpacing.cardGap),
              if (entries.isEmpty)
                const _BillingState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No invoices found',
                  message: 'No billing records match the current filters.',
                ),
              for (final entry in entries) ...[
                _InvoiceHistoryCard(
                  entry: entry,
                  currency: session.clinic.currency,
                  onTap: () => _openInvoice(entry.invoice.id, session),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
              ],
            ],
          );
        },
      ),
    );
  }

  bool _matches(BillingHistoryEntry entry) {
    final state = _stateFor(entry);
    if (_status != 'All' && state.label != _status.toUpperCase()) return false;
    final now = DateTime.now();
    if (_period == '30 days' &&
        entry.invoice.createdAt.isBefore(
          now.subtract(const Duration(days: 30)),
        )) {
      return false;
    }
    if (_period == 'This year' && entry.invoice.createdAt.year != now.year) {
      return false;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      entry.invoice.reference,
      entry.invoice.status,
      entry.animal?.animalName,
      entry.animal?.hospitalNumber,
      entry.owner?.fullName,
      entry.farm?.name,
      entry.invoice.clientNameSnapshot,
      entry.processedBy?.fullName,
    ].whereType<String>().join(' ').toLowerCase().contains(query);
  }

  void _openInitialInvoice(
    List<BillingHistoryEntry> entries,
    UserSession session,
  ) {
    if (_openedInitialInvoice || widget.initialInvoiceId == null) return;
    _openedInitialInvoice = true;
    if (entries.any((entry) => entry.invoice.id == widget.initialInvoiceId)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openInvoice(widget.initialInvoiceId!, session),
      );
    }
  }

  Future<void> _openInvoice(int invoiceId, UserSession session) async {
    final repository = ref.read(clinicRepositoryProvider);
    final detail = await repository.getInvoiceDetail(session, invoiceId);
    if (!mounted) return;
    if (detail == null) {
      _message('Invoice not found in the active clinic.');
      return;
    }
    final entry = await repository
        .watchBillingHistory(session)
        .first
        .then(
          (items) =>
              items.where((item) => item.invoice.id == invoiceId).firstOrNull,
        );
    if (!mounted || entry == null) return;
    final presentation = InvoicePresentationFactory.local(
      detail: detail,
      entry: entry,
      session: session,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => InvoicePreviewSheet(
        invoice: presentation,
        onRecordPayment:
            session.can(Permissions.billingRecordPayment) &&
                detail.invoice.balance > 0
            ? () {
                Navigator.pop(sheetContext);
                _recordPayment(invoiceId, detail.invoice.balance, session);
              }
            : null,
        onRefund:
            session.can(Permissions.billingRefund) &&
                detail.invoice.amountPaid > detail.invoice.refundTotal
            ? () {
                Navigator.pop(sheetContext);
                _refund(invoiceId, session);
              }
            : null,
        onVoid:
            session.can(Permissions.billingVoid) &&
                detail.invoice.status != 'Voided'
            ? () {
                Navigator.pop(sheetContext);
                _void(invoiceId, session);
              }
            : null,
        onPrint: session.can(Permissions.billingPrint)
            ? () => _print(presentation)
            : null,
      ),
    );
  }

  Future<void> _recordPayment(
    int invoiceId,
    double outstanding,
    UserSession session,
  ) async {
    final result = await showPaymentCaptureDialog(
      context: context,
      outstanding: outstanding,
      currency: session.clinic.currency,
    );
    if (result == null) return;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordInvoicePayment(
            session: session,
            invoiceId: invoiceId,
            amount: result.amount,
            paymentMethod: result.method,
            paidAt: result.paidAt,
            reference: result.reference,
          );
      _message('Payment recorded.');
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _refund(int invoiceId, UserSession session) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Process Refund'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Refund amount'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(amount.text.trim());
              if (parsed != null &&
                  parsed > 0 &&
                  reason.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, (parsed, reason.text.trim()));
              }
            },
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    amount.dispose();
    reason.dispose();
    if (result == null) return;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .refundInvoicePayment(
            session: session,
            invoiceId: invoiceId,
            amount: result.$1,
            reason: result.$2,
          );
      _message('Refund recorded.');
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _void(int invoiceId, UserSession session) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void this invoice?'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            helperText: 'Voiding is permanent and creates an audit event.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Void Invoice'),
          ),
        ],
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .voidInvoice(session: session, invoiceId: invoiceId, reason: value);
      _message('Invoice voided.');
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _print(InvoicePresentation presentation) async {
    final bytes = await const InvoicePdfService().build(presentation);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.replaceFirst('Bad state: ', ''))),
    );
  }
}

InvoicePaymentState _stateFor(BillingHistoryEntry entry) =>
    resolveInvoicePaymentState(
      status: entry.invoice.status,
      total: entry.invoice.total,
      amountPaid: entry.invoice.amountPaid,
      balance: entry.invoice.balance,
    );

class _InvoiceHistoryCard extends StatelessWidget {
  const _InvoiceHistoryCard({
    required this.entry,
    required this.currency,
    required this.onTap,
  });

  final BillingHistoryEntry entry;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AveraSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.all(AveraSpacing.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.invoice.reference,
                    style: averaText(context).listItemTitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.farm != null
                        ? '${entry.farm!.name} - Farm visit'
                        : '${entry.animal?.animalName ?? 'Patient'} - '
                              '${entry.animal?.hospitalNumber ?? 'No hospital number'}',
                    style: averaText(context).listItemSubtitle,
                  ),
                  Text(
                    entry.owner?.fullName ??
                        entry.invoice.clientNameSnapshot ??
                        'Farm client',
                    style: averaText(context).caption,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat.yMMMd().add_jm().format(entry.invoice.createdAt),
                    style: averaText(context).caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _BillingStatus(_stateFor(entry)),
                const SizedBox(height: 10),
                Text(
                  '$currency ${entry.invoice.total.toStringAsFixed(2)}',
                  style: averaText(
                    context,
                  ).fieldValue.copyWith(fontWeight: FontWeight.w700),
                ),
                if (entry.invoice.balance > 0)
                  Text(
                    'Due $currency '
                    '${entry.invoice.balance.toStringAsFixed(2)}',
                    style: averaText(context).caption,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _BillingStatus extends StatelessWidget {
  const _BillingStatus(this.state);

  final InvoicePaymentState state;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final color = switch (state) {
      InvoicePaymentState.paid => semantic.success,
      InvoicePaymentState.partiallyPaid ||
      InvoicePaymentState.unpaid => semantic.warning,
      InvoicePaymentState.refunded ||
      InvoicePaymentState.voided ||
      InvoicePaymentState.cancelled => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        state.label,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BillingState extends StatelessWidget {
  const _BillingState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: averaText(context).sectionTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: averaText(context).sectionSubtitle,
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
