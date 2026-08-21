import 'package:intl/intl.dart';

import '../../../core/services/clinic_document_branding.dart';

enum InvoicePaymentState {
  draft,
  unpaid,
  partiallyPaid,
  paid,
  refunded,
  voided,
  cancelled,
}

InvoicePaymentState resolveInvoicePaymentState({
  required String status,
  required double total,
  required double amountPaid,
  required double balance,
}) {
  final normalized = status.trim().toLowerCase();
  if (normalized == 'draft') return InvoicePaymentState.draft;
  if (normalized == 'voided') return InvoicePaymentState.voided;
  if (normalized == 'cancelled') return InvoicePaymentState.cancelled;
  if (normalized == 'refunded') return InvoicePaymentState.refunded;
  if (amountPaid <= 0 || balance >= total - 0.001) {
    return InvoicePaymentState.unpaid;
  }
  if (balance > 0.001 && amountPaid < total) {
    return InvoicePaymentState.partiallyPaid;
  }
  return InvoicePaymentState.paid;
}

extension InvoicePaymentStateLabel on InvoicePaymentState {
  String get label => switch (this) {
    InvoicePaymentState.draft => 'DRAFT',
    InvoicePaymentState.unpaid => 'UNPAID',
    InvoicePaymentState.partiallyPaid => 'PARTIALLY PAID',
    InvoicePaymentState.paid => 'PAID',
    InvoicePaymentState.refunded => 'REFUNDED',
    InvoicePaymentState.voided => 'VOIDED',
    InvoicePaymentState.cancelled => 'CANCELLED',
  };
}

typedef ClinicInvoiceBranding = ClinicDocumentBranding;

class InvoicePresentationLine {
  const InvoicePresentationLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.patientId,
    this.patientName,
    this.hospitalNumber,
  });

  final String description;
  final double quantity;
  final double unitPrice;
  final double amount;
  final String? patientId;
  final String? patientName;
  final String? hospitalNumber;

  bool get isShared => patientId == null;
}

class InvoicePresentationSection {
  const InvoicePresentationSection({
    required this.title,
    required this.lines,
    this.patientId,
    this.hospitalNumber,
  });

  final String title;
  final String? patientId;
  final String? hospitalNumber;
  final List<InvoicePresentationLine> lines;

  bool get isShared => patientId == null;
  double get subtotal => lines.fold(0, (sum, line) => sum + line.amount);
}

class InvoicePaymentPresentation {
  const InvoicePaymentPresentation({
    required this.amount,
    required this.method,
    required this.paidAt,
    this.reference,
  });

  final double amount;
  final String method;
  final DateTime paidAt;
  final String? reference;
}

class InvoicePresentation {
  InvoicePresentation({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.issuedAt,
    required this.clientName,
    required this.clientPhone,
    required this.branding,
    required this.lines,
    required this.total,
    required this.amountPaid,
    required this.balance,
    required this.paymentState,
    this.discount = 0,
    this.tax = 0,
    this.payments = const [],
  }) : sections = _group(lines);

  final String invoiceId;
  final String invoiceNumber;
  final DateTime issuedAt;
  final String clientName;
  final String? clientPhone;
  final ClinicInvoiceBranding branding;
  final List<InvoicePresentationLine> lines;
  final List<InvoicePresentationSection> sections;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;
  final double balance;
  final InvoicePaymentState paymentState;
  final List<InvoicePaymentPresentation> payments;

  double get subtotal =>
      sections.fold(0, (sum, section) => sum + section.subtotal);
  InvoicePaymentPresentation? get latestPayment => payments.isEmpty
      ? null
      : (payments.toList()..sort((a, b) => b.paidAt.compareTo(a.paidAt))).first;

  static List<InvoicePresentationSection> _group(
    List<InvoicePresentationLine> lines,
  ) {
    final patientGroups = <String, List<InvoicePresentationLine>>{};
    final shared = <InvoicePresentationLine>[];
    for (final line in lines) {
      if (line.isShared) {
        shared.add(line);
      } else {
        patientGroups.putIfAbsent(line.patientId!, () => []).add(line);
      }
    }
    final sections = <InvoicePresentationSection>[
      for (final entry in patientGroups.entries)
        InvoicePresentationSection(
          patientId: entry.key,
          title: entry.value.first.patientName?.trim().isNotEmpty == true
              ? entry.value.first.patientName!.trim()
              : 'Animal',
          hospitalNumber: entry.value.first.hospitalNumber,
          lines: List.unmodifiable(entry.value),
        ),
      if (shared.isNotEmpty)
        InvoicePresentationSection(
          title: 'General / Shared',
          lines: List.unmodifiable(shared),
        ),
    ];
    return List.unmodifiable(sections);
  }
}

String formatInvoiceMoney(String currency, num value) {
  final decimals = value % 1 == 0 ? 0 : 2;
  return '$currency ${NumberFormat.currency(symbol: '', decimalDigits: decimals).format(value).trim()}';
}
