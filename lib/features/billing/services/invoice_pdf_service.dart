import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/clinic_document_branding.dart';
import '../models/invoice_presentation.dart';

class InvoicePdfService {
  const InvoicePdfService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<Uint8List> build(InvoicePresentation invoice) async {
    final brandingService = ClinicDocumentBrandingService(client: _client);
    final logo = await brandingService.loadLogo(invoice.branding.logoReference);
    final accent = brandingService.accentColor(invoice.branding);
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(34),
        ),
        header: (_) => _header(invoice, logo, accent),
        build: (_) => [
          pw.SizedBox(height: 18),
          _metadata(invoice),
          pw.SizedBox(height: 20),
          for (final section in invoice.sections) ...[
            ..._section(invoice, section),
            pw.SizedBox(height: 18),
          ],
          _totals(invoice, accent),
          pw.SizedBox(height: 42),
          _footer(invoice),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _header(
    InvoicePresentation invoice,
    pw.MemoryImage? logo,
    PdfColor accent,
  ) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    color: PdfColor.fromHex('#F2F4F5'),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 56,
            height: 56,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 12),
        ] else ...[
          pw.Container(
            width: 56,
            height: 56,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              _initials(invoice.branding.clinicName),
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                invoice.branding.clinicName,
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (_present(invoice.branding.address))
                pw.Text(invoice.branding.address!),
              pw.Wrap(
                spacing: 8,
                children: [
                  if (_present(invoice.branding.phone))
                    pw.Text(invoice.branding.phone!),
                  if (_present(invoice.branding.email))
                    pw.Text(invoice.branding.email!),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'INVOICE',
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 7),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: pw.BoxDecoration(
                color: _statusColor(invoice.paymentState),
                borderRadius: pw.BorderRadius.circular(20),
              ),
              child: pw.Text(
                invoice.paymentState.label,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  pw.Widget _metadata(InvoicePresentation invoice) => pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
    children: [
      pw.TableRow(
        children: [
          _metadataCell('INVOICE NUMBER', invoice.invoiceNumber),
          _metadataCell(
            'DATE ISSUED',
            DateFormat.yMMMMd().format(invoice.issuedAt),
          ),
        ],
      ),
      pw.TableRow(
        children: [
          _metadataCell('CLIENT', invoice.clientName),
          _metadataCell(
            'PHONE',
            _present(invoice.clientPhone)
                ? invoice.clientPhone!
                : 'Not provided',
          ),
        ],
      ),
    ],
  );

  pw.Widget _metadataCell(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(0, 0, 16, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );

  List<pw.Widget> _section(
    InvoicePresentation invoice,
    InvoicePresentationSection section,
  ) => [
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: section.title,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (_present(section.hospitalNumber))
                pw.TextSpan(
                  text: '  |  ${section.hospitalNumber}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 7),
      ],
    ),
    pw.TableHelper.fromTextArray(
      headers: const ['DESCRIPTION', 'QTY', 'UNIT PRICE', 'AMOUNT'],
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF0EEEB),
      ),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9),
      columnWidths: const {
        0: pw.FlexColumnWidth(3.2),
        1: pw.FlexColumnWidth(0.7),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
      },
      data: [
        for (final line in section.lines)
          [
            line.description,
            _quantity(line.quantity),
            formatInvoiceMoney(invoice.branding.currency, line.unitPrice),
            formatInvoiceMoney(invoice.branding.currency, line.amount),
          ],
      ],
    ),
    pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'Subtotal - ${section.title}: ${formatInvoiceMoney(invoice.branding.currency, section.subtotal)}',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ),
      ),
    ),
  ];

  pw.Widget _totals(InvoicePresentation invoice, PdfColor accent) => pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.SizedBox(
      width: 275,
      child: pw.Column(
        children: [
          _totalRow('Subtotal', invoice.subtotal, invoice),
          _totalRow('Discount', invoice.discount, invoice),
          _totalRow('Tax (VAT)', invoice.tax, invoice),
          if (invoice.amountPaid > 0)
            _totalRow('Amount Paid', invoice.amountPaid, invoice),
          if (invoice.balance > 0)
            _totalRow('Balance', invoice.balance, invoice),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            color: PdfColor.fromHex('#F0EEEB'),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Text(
                  formatInvoiceMoney(invoice.branding.currency, invoice.total),
                  style: pw.TextStyle(
                    fontSize: 14,
                    color: accent,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  pw.Widget _totalRow(
    String label,
    double value,
    InvoicePresentation invoice,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(child: pw.Text(label)),
        pw.Text(formatInvoiceMoney(invoice.branding.currency, value)),
      ],
    ),
  );

  pw.Widget _footer(InvoicePresentation invoice) {
    final payment = invoice.latestPayment;
    final paymentText = switch (invoice.paymentState) {
      InvoicePaymentState.paid when payment != null =>
        'Payment confirmed via ${payment.method} on ${DateFormat.yMMMd().format(payment.paidAt)}.',
      InvoicePaymentState.partiallyPaid when payment != null =>
        'Latest payment via ${payment.method} on ${DateFormat.yMMMd().format(payment.paidAt)}. Outstanding balance: ${formatInvoiceMoney(invoice.branding.currency, invoice.balance)}.',
      InvoicePaymentState.unpaid =>
        'Payment has not yet been recorded for this invoice.',
      _ => '',
    };
    final contacts = [
      invoice.branding.email,
      invoice.branding.phone,
    ].where((value) => _present(value)).join(' or ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.Text(
          "Thank you for trusting us with your animals' care.",
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        if (paymentText.isNotEmpty) pw.Text(paymentText),
        if (contacts.isNotEmpty)
          pw.Text('Questions about this invoice? Contact $contacts.'),
      ],
    );
  }

  PdfColor _statusColor(InvoicePaymentState state) => switch (state) {
    InvoicePaymentState.paid => PdfColor.fromHex('#23855A'),
    InvoicePaymentState.partiallyPaid => PdfColor.fromHex('#B27A12'),
    InvoicePaymentState.unpaid ||
    InvoicePaymentState.cancelled ||
    InvoicePaymentState.voided => PdfColor.fromHex('#B54848'),
    _ => PdfColor.fromHex('#667085'),
  };

  bool _present(String? value) => value?.trim().isNotEmpty == true;
  String _quantity(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  String _initials(String value) => value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0].toUpperCase())
      .join();
}
