import '../../../core/repositories/clinic_repository.dart';
import '../../../core/services/clinic_document_branding.dart';
import '../models/invoice_presentation.dart';

class InvoicePresentationFactory {
  const InvoicePresentationFactory._();

  static InvoicePresentation local({
    required InvoiceDetail detail,
    required BillingHistoryEntry entry,
    required UserSession session,
  }) {
    final animals = {for (final animal in detail.animals) animal.id: animal};
    final farmUnits = {for (final unit in detail.farmUnits) unit.id: unit};
    final lines = <InvoicePresentationLine>[
      for (final line in detail.products)
        InvoicePresentationLine(
          description: line.productNameSnapshot,
          quantity: line.quantity.toDouble(),
          unitPrice: line.unitPrice,
          amount: line.lineTotal,
          patientId: line.animalId?.toString(),
          patientName: animals[line.animalId]?.animalName,
          hospitalNumber: animals[line.animalId]?.hospitalNumber,
        ),
      for (final line in detail.services)
        InvoicePresentationLine(
          description: line.description,
          quantity: 1,
          unitPrice: line.amount,
          amount: line.amount,
          patientId: line.animalId?.toString(),
          hospitalNumber: animals[line.animalId]?.hospitalNumber,
          patientName:
              animals[line.animalId]?.animalName ??
              farmUnits[line.farmUnitId]?.name,
        ),
      if (detail.invoice.consultationFee > 0)
        InvoicePresentationLine(
          description: 'Consultation fee',
          quantity: 1,
          unitPrice: detail.invoice.consultationFee,
          amount: detail.invoice.consultationFee,
        ),
      if (detail.invoice.homeServiceFee > 0)
        InvoicePresentationLine(
          description: 'Home service fee',
          quantity: 1,
          unitPrice: detail.invoice.homeServiceFee,
          amount: detail.invoice.homeServiceFee,
        ),
    ];
    return InvoicePresentation(
      invoiceId: detail.invoice.id.toString(),
      invoiceNumber: detail.invoice.reference,
      issuedAt: detail.invoice.createdAt,
      clientName:
          entry.owner?.fullName ??
          detail.invoice.clientNameSnapshot ??
          entry.farm?.name ??
          'Farm client',
      clientPhone: entry.owner?.phone ?? detail.invoice.clientPhoneSnapshot,
      branding: branding(session),
      lines: lines,
      total: detail.invoice.total,
      amountPaid: detail.invoice.amountPaid,
      balance: detail.invoice.balance,
      paymentState: resolveInvoicePaymentState(
        status: detail.invoice.status,
        total: detail.invoice.total,
        amountPaid: detail.invoice.amountPaid,
        balance: detail.invoice.balance,
      ),
      payments: [
        for (final payment in detail.payments)
          if (payment.transactionType == 'Payment')
            InvoicePaymentPresentation(
              amount: payment.amount,
              method: payment.paymentMethod,
              paidAt: payment.createdAt,
              reference: payment.reason?.trim().isNotEmpty == true
                  ? payment.reason
                  : payment.receiptNumber,
            ),
      ],
    );
  }

  static InvoicePresentation remote({
    required Map<String, dynamic> payload,
    required UserSession session,
  }) {
    final invoice = _map(payload['invoice']);
    final lineItems = _maps(payload['lineItems']);
    final payments = _maps(payload['payments']);
    final total = _number(invoice['total']);
    final amountPaid = _number(invoice['amount_paid']);
    final balance = _number(invoice['balance']);
    return InvoicePresentation(
      invoiceId: '${invoice['invoice_id'] ?? ''}',
      invoiceNumber: '${invoice['invoice_number'] ?? ''}',
      issuedAt:
          DateTime.tryParse('${invoice['issued_at'] ?? ''}')?.toLocal() ??
          DateTime.now(),
      clientName: '${invoice['owner_name'] ?? 'Client'}',
      clientPhone: invoice['owner_phone']?.toString(),
      branding: branding(session),
      lines: [
        for (final line in lineItems)
          InvoicePresentationLine(
            description: '${line['description'] ?? 'Invoice item'}',
            quantity: _number(line['quantity'], fallback: 1),
            unitPrice: _number(line['unit_price']),
            amount: _number(line['line_total']),
            patientId: line['patient_id']?.toString(),
            patientName: line['patient_name']?.toString(),
            hospitalNumber: line['hospital_number']?.toString(),
          ),
      ],
      discount: _number(invoice['discount']),
      tax: _number(invoice['tax']),
      total: total,
      amountPaid: amountPaid,
      balance: balance,
      paymentState: resolveInvoicePaymentState(
        status: '${invoice['status'] ?? ''}',
        total: total,
        amountPaid: amountPaid,
        balance: balance,
      ),
      payments: [
        for (final payment in payments)
          InvoicePaymentPresentation(
            amount: _number(payment['amount']),
            method: '${payment['method'] ?? 'Other'}',
            paidAt:
                DateTime.tryParse('${payment['paid_at'] ?? ''}')?.toLocal() ??
                DateTime.now(),
            reference: payment['reference']?.toString(),
          ),
      ],
    );
  }

  static ClinicInvoiceBranding branding(UserSession session) {
    return ClinicDocumentBranding.fromSession(session);
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : const [];

  static double _number(Object? value, {double fallback = 0}) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
}
