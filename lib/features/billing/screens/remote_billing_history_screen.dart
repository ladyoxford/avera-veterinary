import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../core/remote/cloud_clinical_state.dart';
import '../../../core/repositories/clinic_repository.dart';
import '../../../core/security/access_control.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/avera_ui.dart';
import '../models/invoice_presentation.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_presentation_factory.dart';
import '../widgets/invoice_preview_sheet.dart';
import '../widgets/payment_capture_dialog.dart';

class RemoteBillingHistoryScreen extends ConsumerStatefulWidget {
  const RemoteBillingHistoryScreen({
    super.key,
    required this.session,
    this.initialInvoiceId,
    this.initialContext,
    this.initialFarmId,
  });

  final UserSession session;
  final String? initialInvoiceId;
  final String? initialContext;
  final String? initialFarmId;

  @override
  ConsumerState<RemoteBillingHistoryScreen> createState() =>
      _RemoteBillingHistoryScreenState();
}

class _RemoteBillingHistoryScreenState
    extends ConsumerState<RemoteBillingHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';
  String _status = 'All';
  String _period = 'All time';
  late String _invoiceContext;
  bool _newestFirst = true;
  bool _openedInitialInvoice = false;

  @override
  void initState() {
    super.initState();
    _invoiceContext = switch (widget.initialContext?.toLowerCase()) {
      'farm' => 'Farm',
      'patient' || 'clinic' => 'Patient / Clinic',
      _ => 'All',
    };
    _reload();
  }

  void _reload() {
    _future = _loadInvoiceLedger();
  }

  Future<List<Map<String, dynamic>>> _loadInvoiceLedger() async {
    final source = ref.read(clinicalRemoteDataSourceProvider);
    final invoices = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final result = await source.invoices(page: page, pageSize: 100);
      invoices.addAll(result.items);
      if (!result.hasNextPage) return invoices;
      page += 1;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Billing History'),
      actions: [
        IconButton(
          tooltip: _newestFirst ? 'Oldest first' : 'Newest first',
          onPressed: () => setState(() => _newestFirst = !_newestFirst),
          icon: Icon(_newestFirst ? Icons.south_rounded : Icons.north_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _RemoteBillingState(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load billing history',
            message: 'The clinic invoice ledger could not be refreshed.',
            action: FilledButton(
              onPressed: () => setState(_reload),
              child: const Text('Retry'),
            ),
          );
        }
        final invoices =
            (snapshot.data ?? const [])
                .map(_RemoteInvoiceSummary.fromJson)
                .where(_matches)
                .toList()
              ..sort(
                (a, b) => _newestFirst
                    ? b.issuedAt.compareTo(a.issuedAt)
                    : a.issuedAt.compareTo(b.issuedAt),
              );
        _openInitialInvoice(invoices);
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await _future;
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  hintText: 'Search invoice, patient, owner, or phone',
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
                      'Cancelled',
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
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(
                    value: 'Patient / Clinic',
                    label: Text('Patient / Clinic'),
                  ),
                  ButtonSegment(value: 'Farm', label: Text('Farm')),
                ],
                selected: {_invoiceContext},
                onSelectionChanged: (value) =>
                    setState(() => _invoiceContext = value.first),
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
              if (invoices.isEmpty)
                const _RemoteBillingState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No invoices found',
                  message: 'No billing records match the current filters.',
                ),
              for (final invoice in invoices) ...[
                _RemoteInvoiceCard(
                  invoice: invoice,
                  currency: widget.session.clinic.currency,
                  onTap: () => _openInvoice(invoice.id),
                ),
                const SizedBox(height: AveraSpacing.cardGap),
              ],
            ],
          ),
        );
      },
    ),
  );

  bool _matches(_RemoteInvoiceSummary invoice) {
    if (_invoiceContext == 'Farm' && !invoice.isFarm) return false;
    if (_invoiceContext == 'Patient / Clinic' && invoice.isFarm) return false;
    if (widget.initialFarmId != null &&
        invoice.farmId != widget.initialFarmId) {
      return false;
    }
    if (_status != 'All' && invoice.state.label != _status.toUpperCase()) {
      return false;
    }
    final now = DateTime.now();
    if (_period == '30 days' &&
        invoice.issuedAt.isBefore(now.subtract(const Duration(days: 30)))) {
      return false;
    }
    if (_period == 'This year' && invoice.issuedAt.year != now.year) {
      return false;
    }
    final query = _query.trim().toLowerCase();
    return query.isEmpty || invoice.searchable.contains(query);
  }

  void _openInitialInvoice(List<_RemoteInvoiceSummary> invoices) {
    if (_openedInitialInvoice || widget.initialInvoiceId == null) return;
    _openedInitialInvoice = true;
    if (invoices.any((invoice) => invoice.id == widget.initialInvoiceId)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openInvoice(widget.initialInvoiceId!),
      );
    }
  }

  Future<void> _openInvoice(String invoiceId) async {
    try {
      final payload = await ref
          .read(clinicalRemoteDataSourceProvider)
          .invoice(invoiceId);
      final invoice = InvoicePresentationFactory.remote(
        payload: payload,
        session: widget.session,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => InvoicePreviewSheet(
          invoice: invoice,
          onRecordPayment:
              widget.session.can(Permissions.billingRecordPayment) &&
                  invoice.balance > 0 &&
                  !{
                    InvoicePaymentState.cancelled,
                    InvoicePaymentState.voided,
                    InvoicePaymentState.refunded,
                  }.contains(invoice.paymentState)
              ? () {
                  Navigator.pop(sheetContext);
                  _recordPayment(invoice);
                }
              : null,
          onPrint: widget.session.can(Permissions.billingPrint)
              ? () => _print(invoice)
              : null,
        ),
      );
    } catch (_) {
      _message(
        'Unable to open this invoice. Pull down to refresh and try again.',
      );
    }
  }

  Future<void> _recordPayment(InvoicePresentation invoice) async {
    final result = await showPaymentCaptureDialog(
      context: context,
      outstanding: invoice.balance,
      currency: invoice.branding.currency,
    );
    if (result == null) return;
    try {
      await ref
          .read(clinicalRemoteDataSourceProvider)
          .recordInvoicePayment(
            invoiceId: invoice.invoiceId,
            payload: {
              'submissionId': const Uuid().v4(),
              'amount': result.amount,
              'method': result.method,
              'paidAt': result.paidAt.toUtc().toIso8601String(),
              'reference': result.reference,
            },
          );
      if (!mounted) return;
      setState(_reload);
      _message('Payment recorded.');
    } catch (_) {
      _message('The payment could not be recorded. No balance was changed.');
    }
  }

  Future<void> _print(InvoicePresentation invoice) async {
    try {
      final bytes = await const InvoicePdfService().build(invoice);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${invoice.invoiceNumber}.pdf',
      );
    } catch (_) {
      _message('The invoice PDF could not be prepared.');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

class _RemoteInvoiceSummary {
  const _RemoteInvoiceSummary({
    required this.id,
    required this.number,
    required this.ownerName,
    required this.ownerPhone,
    required this.patientNames,
    required this.issuedAt,
    required this.total,
    required this.amountPaid,
    required this.balance,
    required this.state,
    required this.contextType,
    required this.farmId,
    required this.farmName,
  });

  final String id;
  final String number;
  final String ownerName;
  final String ownerPhone;
  final String patientNames;
  final DateTime issuedAt;
  final double total;
  final double amountPaid;
  final double balance;
  final InvoicePaymentState state;
  final String contextType;
  final String? farmId;
  final String? farmName;

  bool get isFarm => contextType == 'farm_visit';

  String get searchable =>
      '$number $ownerName $ownerPhone $patientNames ${farmName ?? ''} ${state.label}'
          .toLowerCase();

  factory _RemoteInvoiceSummary.fromJson(Map<String, dynamic> json) {
    final total = _number(json['total']);
    final paid = _number(json['amount_paid']);
    final balance = _number(json['balance']);
    return _RemoteInvoiceSummary(
      id: '${json['invoice_id'] ?? ''}',
      number: '${json['invoice_number'] ?? 'Invoice'}',
      ownerName: '${json['owner_name'] ?? 'Client'}',
      ownerPhone: '${json['owner_phone'] ?? ''}',
      patientNames:
          '${json['patient_names'] ?? json['patient_name'] ?? 'General / Shared'}',
      issuedAt:
          DateTime.tryParse('${json['issued_at'] ?? ''}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      total: total,
      amountPaid: paid,
      balance: balance,
      state: resolveInvoicePaymentState(
        status: '${json['status'] ?? ''}',
        total: total,
        amountPaid: paid,
        balance: balance,
      ),
      contextType: '${json['context_type'] ?? 'patient'}',
      farmId: json['farm_id']?.toString(),
      farmName: json['farm_name']?.toString(),
    );
  }

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

class _RemoteInvoiceCard extends StatelessWidget {
  const _RemoteInvoiceCard({
    required this.invoice,
    required this.currency,
    required this.onTap,
  });

  final _RemoteInvoiceSummary invoice;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AveraSpacing.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          invoice.number,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        formatInvoiceMoney(currency, invoice.total),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    invoice.isFarm
                        ? (invoice.farmName ?? invoice.ownerName)
                        : invoice.patientNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${invoice.ownerName}${invoice.ownerPhone.isEmpty ? '' : ' • ${invoice.ownerPhone}'}',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _StatusBadge(state: invoice.state),
                      const Spacer(),
                      Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatShortDate(invoice.issuedAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final InvoicePaymentState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(state.label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _RemoteBillingState extends StatelessWidget {
  const _RemoteBillingState({
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
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}
