import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';

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
                      'Pending',
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
    if (_status != 'All' && entry.invoice.status != _status) return false;
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
      entry.animal.animalName,
      entry.animal.hospitalNumber,
      entry.owner.fullName,
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _InvoiceDetailSheet(
        detail: detail,
        entry: entry,
        session: session,
        onPayment: session.can(Permissions.billingRecordPayment)
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
            ? () => _print(detail, entry, session)
            : null,
      ),
    );
  }

  Future<void> _recordPayment(
    int invoiceId,
    double outstanding,
    UserSession session,
  ) async {
    final amount = TextEditingController(
      text: outstanding > 0 ? outstanding.toStringAsFixed(2) : '',
    );
    var method = 'Cash';
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: method,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(
                    value: 'Bank transfer',
                    child: Text('Bank transfer'),
                  ),
                  DropdownMenuItem(value: 'Card', child: Text('Card')),
                  DropdownMenuItem(
                    value: 'Mobile money',
                    child: Text('Mobile money'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
                decoration: const InputDecoration(labelText: 'Method'),
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
                if (parsed != null && parsed > 0) {
                  Navigator.pop(dialogContext, (parsed, method));
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (result == null) return;
    try {
      await ref
          .read(clinicRepositoryProvider)
          .recordInvoicePayment(
            session: session,
            invoiceId: invoiceId,
            amount: result.$1,
            paymentMethod: result.$2,
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

  Future<void> _print(
    InvoiceDetail detail,
    BillingHistoryEntry entry,
    UserSession session,
  ) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text(
            session.clinic.clinicName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('Invoice ${detail.invoice.reference}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'Animals: ${detail.animals.map((animal) => '${animal.animalName} (${animal.hospitalNumber})').join(', ')}',
          ),
          pw.Text('Owner: ${entry.owner.fullName}'),
          pw.Text('Status: ${detail.invoice.status}'),
          pw.SizedBox(height: 16),
          for (final line in detail.products)
            pw.Text(
              '${_linePatientName(detail, line.animalId)}: '
              '${line.productNameSnapshot} x ${line.quantity}  '
              '${session.clinic.currency} ${line.lineTotal.toStringAsFixed(2)}',
            ),
          for (final line in detail.services)
            pw.Text(
              '${_linePatientName(detail, line.animalId)}: ${line.description}  '
              '${session.clinic.currency} ${line.amount.toStringAsFixed(2)}',
            ),
          pw.Divider(),
          pw.Text(
            'Total: ${session.clinic.currency} '
            '${detail.invoice.total.toStringAsFixed(2)}',
          ),
          pw.Text(
            'Paid: ${session.clinic.currency} '
            '${detail.invoice.amountPaid.toStringAsFixed(2)}',
          ),
          pw.Text(
            'Refunded: ${session.clinic.currency} '
            '${detail.invoice.refundTotal.toStringAsFixed(2)}',
          ),
          pw.Text(
            'Balance: ${session.clinic.currency} '
            '${detail.invoice.balance.toStringAsFixed(2)}',
          ),
          if (detail.payments.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Payment history',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            for (final payment in detail.payments)
              pw.Text(
                '${payment.receiptNumber} - ${payment.transactionType} - '
                '${session.clinic.currency} ${payment.amount.toStringAsFixed(2)}',
              ),
          ],
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.replaceFirst('Bad state: ', ''))),
    );
  }
}

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
                    '${entry.animal.animalName} - '
                    '${entry.animal.hospitalNumber}',
                    style: averaText(context).listItemSubtitle,
                  ),
                  Text(entry.owner.fullName, style: averaText(context).caption),
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
                _BillingStatus(entry.invoice.status),
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

class _InvoiceDetailSheet extends StatelessWidget {
  const _InvoiceDetailSheet({
    required this.detail,
    required this.entry,
    required this.session,
    this.onPayment,
    this.onRefund,
    this.onVoid,
    this.onPrint,
  });

  final InvoiceDetail detail;
  final BillingHistoryEntry entry;
  final UserSession session;
  final VoidCallback? onPayment;
  final VoidCallback? onRefund;
  final VoidCallback? onVoid;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.82,
    minChildSize: 0.5,
    maxChildSize: 0.96,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                detail.invoice.reference,
                style: averaText(context).sectionTitle,
              ),
            ),
            _BillingStatus(detail.invoice.status),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          detail.animals
              .map(
                (animal) => '${animal.animalName} - ${animal.hospitalNumber}',
              )
              .join('\n'),
          style: averaText(context).listItemSubtitle,
        ),
        Text(entry.owner.fullName, style: averaText(context).caption),
        const SizedBox(height: 20),
        AveraSurfaceCard(
          child: Column(
            children: [
              _AmountLine(
                label: 'Invoice total',
                amount: detail.invoice.total,
                currency: session.clinic.currency,
              ),
              _AmountLine(
                label: 'Paid',
                amount: detail.invoice.amountPaid,
                currency: session.clinic.currency,
              ),
              _AmountLine(
                label: 'Refunded',
                amount: detail.invoice.refundTotal,
                currency: session.clinic.currency,
              ),
              _AmountLine(
                label: 'Outstanding',
                amount: detail.invoice.balance,
                currency: session.clinic.currency,
                emphasized: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Invoice Items', style: averaText(context).sectionLabel),
        const SizedBox(height: 8),
        AveraSurfaceCard(
          child: Column(
            children: [
              for (final line in detail.products)
                _LineItem(
                  title: line.productNameSnapshot,
                  subtitle:
                      '${_linePatientName(detail, line.animalId)} | Quantity ${line.quantity}',
                  amount: line.lineTotal,
                  currency: session.clinic.currency,
                ),
              for (final line in detail.services)
                _LineItem(
                  title: line.description,
                  subtitle: _linePatientName(detail, line.animalId),
                  amount: line.amount,
                  currency: session.clinic.currency,
                ),
            ],
          ),
        ),
        if (detail.payments.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Payment History', style: averaText(context).sectionLabel),
          const SizedBox(height: 8),
          AveraSurfaceCard(
            child: Column(
              children: [
                for (final payment in detail.payments)
                  _LineItem(
                    title: payment.receiptNumber,
                    subtitle:
                        '${payment.transactionType} - ${payment.paymentMethod}',
                    amount: payment.transactionType == 'Refund'
                        ? -payment.amount
                        : payment.amount,
                    currency: session.clinic.currency,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onPayment != null && detail.invoice.balance > 0)
              FilledButton.icon(
                onPressed: onPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record Payment'),
              ),
            if (onRefund != null)
              OutlinedButton.icon(
                onPressed: onRefund,
                icon: const Icon(Icons.currency_exchange_rounded),
                label: const Text('Refund'),
              ),
            if (onPrint != null)
              OutlinedButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print / PDF'),
              ),
            if (onVoid != null)
              TextButton.icon(
                onPressed: onVoid,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Void'),
              ),
          ],
        ),
      ],
    ),
  );
}

String _linePatientName(InvoiceDetail detail, int? animalId) {
  if (animalId == null) return 'General / Shared';
  return detail.animals
          .where((animal) => animal.id == animalId)
          .firstOrNull
          ?.animalName ??
      'Animal';
}

class _BillingStatus extends StatelessWidget {
  const _BillingStatus(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final color = switch (status) {
      'Paid' => semantic.success,
      'Partially paid' || 'Pending' => semantic.warning,
      'Refunded' || 'Voided' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: averaText(
          context,
        ).caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.amount,
    required this.currency,
    this.emphasized = false,
  });

  final String label;
  final double amount;
  final String currency;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: averaText(context).listItemSubtitle),
        ),
        Text(
          '$currency ${amount.toStringAsFixed(2)}',
          style: emphasized
              ? averaText(context).listItemTitle
              : averaText(context).fieldValue,
        ),
      ],
    ),
  );
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
  });

  final String title;
  final String subtitle;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: averaText(context).fieldValue),
              Text(subtitle, style: averaText(context).caption),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$currency ${amount.toStringAsFixed(2)}',
          style: averaText(context).fieldValue,
        ),
      ],
    ),
  );
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
