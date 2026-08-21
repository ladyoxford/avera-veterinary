import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/avera_ui.dart';
import '../models/invoice_presentation.dart';

class InvoicePreviewSheet extends StatelessWidget {
  const InvoicePreviewSheet({
    super.key,
    required this.invoice,
    this.onRecordPayment,
    this.onRefund,
    this.onVoid,
    this.onPrint,
  });

  final InvoicePresentation invoice;
  final VoidCallback? onRecordPayment;
  final VoidCallback? onRefund;
  final VoidCallback? onVoid;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) => Material(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _Header(invoice: invoice),
            const SizedBox(height: 22),
            _Metadata(invoice: invoice),
            const SizedBox(height: 22),
            for (final section in invoice.sections) ...[
              _InvoiceSection(invoice: invoice, section: section),
              const SizedBox(height: 18),
            ],
            _Totals(invoice: invoice),
            if (invoice.payments.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                'Payment history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final payment in invoice.payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(
                    formatInvoiceMoney(
                      invoice.branding.currency,
                      payment.amount,
                    ),
                  ),
                  subtitle: Text(
                    '${payment.method} • ${DateFormat.yMMMd().add_jm().format(payment.paidAt)}',
                  ),
                ),
            ],
            if (onRecordPayment != null ||
                onRefund != null ||
                onVoid != null ||
                onPrint != null) ...[
              const SizedBox(height: 24),
              if (onRecordPayment != null)
                AveraPrimaryActionButton(
                  label: 'Record Payment',
                  icon: Icons.payments_outlined,
                  onPressed: onRecordPayment,
                ),
              if (onRecordPayment != null && onPrint != null)
                const SizedBox(height: 12),
              if (onPrint != null)
                OutlinedButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print / PDF'),
                ),
              if (onRefund != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRefund,
                  icon: const Icon(Icons.currency_exchange_rounded),
                  label: const Text('Process Refund'),
                ),
              ],
              if (onVoid != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onVoid,
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Void Invoice'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.invoice});

  final InvoicePresentation invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = invoice.branding.logoReference;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: logo != null && logo.startsWith(RegExp(r'https?://'))
              ? Image.network(
                  logo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _Initials(invoice: invoice),
                )
              : _Initials(invoice: invoice),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                invoice.branding.clinicName,
                style: theme.textTheme.titleLarge,
              ),
              if (invoice.branding.address?.trim().isNotEmpty == true)
                Text(invoice.branding.address!),
              if (invoice.branding.phone?.trim().isNotEmpty == true)
                Text(invoice.branding.phone!),
              if (invoice.branding.email?.trim().isNotEmpty == true)
                Text(invoice.branding.email!),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('INVOICE', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _StatusBadge(state: invoice.paymentState),
          ],
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.invoice});

  final InvoicePresentation invoice;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      invoice.branding.clinicName
          .trim()
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final InvoicePaymentState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (state) {
      InvoicePaymentState.paid => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      InvoicePaymentState.partiallyPaid => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      InvoicePaymentState.unpaid ||
      InvoicePaymentState.cancelled ||
      InvoicePaymentState.voided => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.invoice});

  final InvoicePresentation invoice;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 14,
        children: [
          _MetadataCell(
            width: width,
            label: 'INVOICE NUMBER',
            value: invoice.invoiceNumber,
          ),
          _MetadataCell(
            width: width,
            label: 'DATE ISSUED',
            value: DateFormat.yMMMMd().format(invoice.issuedAt),
          ),
          _MetadataCell(
            width: width,
            label: 'CLIENT',
            value: invoice.clientName,
          ),
          _MetadataCell(
            width: width,
            label: 'PHONE',
            value: invoice.clientPhone?.trim().isNotEmpty == true
                ? invoice.clientPhone!
                : 'Not provided',
          ),
        ],
      );
    },
  );
}

class _MetadataCell extends StatelessWidget {
  const _MetadataCell({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _InvoiceSection extends StatelessWidget {
  const _InvoiceSection({required this.invoice, required this.section});

  final InvoicePresentation invoice;
  final InvoicePresentationSection section;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        [
          section.title,
          section.hospitalNumber,
        ].where((value) => value?.trim().isNotEmpty == true).join(' • '),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      AveraSurfaceCard(
        child: Column(
          children: [
            for (var index = 0; index < section.lines.length; index++) ...[
              if (index > 0) const Divider(),
              _Line(invoice: invoice, line: section.lines[index]),
            ],
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subtotal — ${section.title}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatInvoiceMoney(
                    invoice.branding.currency,
                    section.subtotal,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.invoice, required this.line});

  final InvoicePresentation invoice;
  final InvoicePresentationLine line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.description),
              Text(
                '${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity} × ${formatInvoiceMoney(invoice.branding.currency, line.unitPrice)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatInvoiceMoney(invoice.branding.currency, line.amount),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.invoice});

  final InvoicePresentation invoice;

  @override
  Widget build(BuildContext context) => AveraSurfaceCard(
    child: Column(
      children: [
        _row('Subtotal', invoice.subtotal),
        if (invoice.discount != 0) _row('Discount', invoice.discount),
        if (invoice.tax != 0) _row('Tax (VAT)', invoice.tax),
        if (invoice.amountPaid != 0) _row('Amount paid', invoice.amountPaid),
        if (invoice.balance != 0) _row('Balance', invoice.balance),
        const Divider(),
        _row('INVOICE TOTAL', invoice.total, strong: true),
      ],
    ),
  );

  Widget _row(String label, double value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
          ),
        ),
        Text(
          formatInvoiceMoney(invoice.branding.currency, value),
          style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
        ),
      ],
    ),
  );
}
