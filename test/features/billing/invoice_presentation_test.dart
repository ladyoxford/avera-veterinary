import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/security/access_control.dart';
import 'package:avera/core/services/clinic_document_branding.dart';
import 'package:avera/features/billing/models/invoice_presentation.dart';
import 'package:avera/features/billing/services/invoice_pdf_service.dart';
import 'package:avera/features/billing/services/invoice_presentation_factory.dart';

const _branding = ClinicInvoiceBranding(
  clinicName: 'Avera Veterinary Clinic',
  currency: 'NGN',
  address: 'Amawbia, Nigeria',
  phone: '+234 800 000 0000',
  email: 'clinic@example.com',
);

InvoicePresentation _invoice({
  required List<InvoicePresentationLine> lines,
  required double total,
  double amountPaid = 0,
  required double balance,
  InvoicePaymentState state = InvoicePaymentState.unpaid,
}) => InvoicePresentation(
  invoiceId: 'invoice-1',
  invoiceNumber: 'INV-20260820-123456789',
  issuedAt: DateTime(2026, 8, 20, 10),
  clientName: 'Udechukwu Amawbia',
  clientPhone: '+2348091234567',
  branding: _branding,
  lines: lines,
  total: total,
  amountPaid: amountPaid,
  balance: balance,
  paymentState: state,
);

void main() {
  group('invoice payment state', () {
    test('keeps lifecycle and payment states distinct', () {
      expect(
        resolveInvoicePaymentState(
          status: 'Draft',
          total: 10000,
          amountPaid: 0,
          balance: 10000,
        ),
        InvoicePaymentState.draft,
      );
      expect(
        resolveInvoicePaymentState(
          status: 'Unpaid',
          total: 10000,
          amountPaid: 0,
          balance: 10000,
        ),
        InvoicePaymentState.unpaid,
      );
      expect(
        resolveInvoicePaymentState(
          status: 'Partially paid',
          total: 10000,
          amountPaid: 4000,
          balance: 6000,
        ),
        InvoicePaymentState.partiallyPaid,
      );
      expect(
        resolveInvoicePaymentState(
          status: 'Paid',
          total: 10000,
          amountPaid: 10000,
          balance: 0,
        ),
        InvoicePaymentState.paid,
      );
    });
  });

  group('per-animal presentation', () {
    test('groups two animals and keeps shared charges exceptional', () {
      final invoice = _invoice(
        lines: const [
          InvoicePresentationLine(
            description: 'Consultation',
            quantity: 1,
            unitPrice: 2000,
            amount: 2000,
            patientId: 'bella',
            patientName: 'Bella',
            hospitalNumber: 'AVR-2026-00001',
          ),
          InvoicePresentationLine(
            description: 'Rabies vaccination',
            quantity: 1,
            unitPrice: 8000,
            amount: 8000,
            patientId: 'bella',
            patientName: 'Bella',
            hospitalNumber: 'AVR-2026-00001',
          ),
          InvoicePresentationLine(
            description: 'Routine deworming',
            quantity: 1,
            unitPrice: 20000,
            amount: 20000,
            patientId: 'charlie',
            patientName: 'Charlie',
            hospitalNumber: 'AVR-2026-00002',
          ),
          InvoicePresentationLine(
            description: 'Multi-pet discount adjustment',
            quantity: 1,
            unitPrice: 500,
            amount: 500,
          ),
        ],
        total: 30500,
        balance: 30500,
      );

      expect(invoice.sections.map((section) => section.title), [
        'Bella',
        'Charlie',
        'General / Shared',
      ]);
      expect(invoice.sections[0].subtotal, 10000);
      expect(invoice.sections[1].subtotal, 20000);
      expect(invoice.sections[2].subtotal, 500);
      expect(invoice.subtotal, 30500);
    });

    test('omits General / Shared when every line belongs to an animal', () {
      final invoice = _invoice(
        lines: const [
          InvoicePresentationLine(
            description: 'Consultation',
            quantity: 1,
            unitPrice: 2000,
            amount: 2000,
            patientId: 'bella',
            patientName: 'Bella',
          ),
        ],
        total: 2000,
        balance: 2000,
      );
      expect(
        invoice.sections.any((section) => section.title == 'General / Shared'),
        isFalse,
      );
    });

    test('formats currency with thousands separators', () {
      expect(formatInvoiceMoney('NGN', 20000), 'NGN 20,000');
      expect(formatInvoiceMoney('NGN', 20000.5), 'NGN 20,000.50');
    });

    test('builds a PDF without a configured clinic logo', () async {
      final bytes = await const InvoicePdfService().build(
        _invoice(
          lines: const [
            InvoicePresentationLine(
              description: 'Consultation',
              quantity: 1,
              unitPrice: 2000,
              amount: 2000,
              patientId: 'bella',
              patientName: 'Bella',
              hospitalNumber: 'AVR-2026-00001',
            ),
          ],
          total: 2000,
          amountPaid: 2000,
          balance: 0,
          state: InvoicePaymentState.paid,
        ),
      );
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('builds a PDF with a remotely configured clinic logo', () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://cdn.example.com/clinic.png');
        return http.Response.bytes(
          await File('assets/branding/avera_logo_teal.png').readAsBytes(),
          200,
          headers: const {'content-type': 'image/png'},
        );
      });
      final invoice = InvoicePresentation(
        invoiceId: 'invoice-logo',
        invoiceNumber: 'INV-LOGO',
        issuedAt: DateTime(2026, 8, 20),
        clientName: 'Clinic Client',
        clientPhone: null,
        branding: const ClinicInvoiceBranding(
          clinicName: 'Avera Veterinary Clinic',
          currency: 'NGN',
          logoReference: 'https://cdn.example.com/clinic.png',
        ),
        lines: const [
          InvoicePresentationLine(
            description: 'Consultation',
            quantity: 1,
            unitPrice: 2000,
            amount: 2000,
            patientId: 'bella',
            patientName: 'Bella',
          ),
        ],
        total: 2000,
        amountPaid: 0,
        balance: 2000,
        paymentState: InvoicePaymentState.unpaid,
      );

      final bytes = await InvoicePdfService(client: client).build(invoice);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test(
      'builds a multi-page-safe invoice for three animals and long lines',
      () async {
        final patients = [
          'Bella',
          'Charlie',
          'A Patient With A Very Long Clinical Name',
        ];
        final lines = <InvoicePresentationLine>[
          for (var index = 0; index < 75; index++)
            InvoicePresentationLine(
              description:
                  'Extended veterinary service description number $index with medicine, procedure, monitoring, and follow-up details',
              quantity: 1,
              unitPrice: 1250,
              amount: 1250,
              patientId: 'patient-${index % patients.length}',
              patientName: patients[index % patients.length],
              hospitalNumber:
                  'AVR-2026-${(index % 3 + 1).toString().padLeft(5, '0')}',
            ),
        ];
        final bytes = await const InvoicePdfService().build(
          _invoice(
            lines: lines,
            total: 93750,
            amountPaid: 35000,
            balance: 58750,
            state: InvoicePaymentState.partiallyPaid,
          ),
        );

        expect(bytes.length, greaterThan(10000));
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      },
    );
  });

  test('document branding reads the active clinic identity', () {
    final branding = ClinicDocumentBranding.fromSession(_session);

    expect(branding.clinicName, 'Avera Veterinary Clinic');
    expect(branding.address, 'Amawbia, Awka, Anambra, Nigeria');
    expect(branding.phone, '+2348000000000');
    expect(branding.email, 'clinic@example.com');
    expect(branding.accentHex, '#087F7B');
  });

  test('remote factory preserves patient attribution and payments', () {
    final presentation = InvoicePresentationFactory.remote(
      session: _session,
      payload: {
        'invoice': {
          'invoice_id': 'invoice-1',
          'invoice_number': 'INV-LONG-REFERENCE-123456789',
          'issued_at': '2026-08-20T10:00:00.000Z',
          'owner_name': 'Udechukwu Amawbia',
          'owner_phone': '+2348091234567',
          'status': 'Partially paid',
          'total': '32000.00',
          'amount_paid': '10000.00',
          'balance': '22000.00',
        },
        'lineItems': [
          {
            'description': 'Rabies vaccination',
            'quantity': 1,
            'unit_price': '8000.00',
            'line_total': '8000.00',
            'patient_id': 'bella',
            'patient_name': 'Bella',
            'hospital_number': 'AVR-2026-00001',
          },
        ],
        'payments': [
          {
            'amount': '10000.00',
            'method': 'Transfer',
            'paid_at': '2026-08-20T11:00:00.000Z',
            'reference': 'TRX-1',
          },
        ],
      },
    );

    expect(presentation.sections.single.title, 'Bella');
    expect(presentation.paymentState, InvoicePaymentState.partiallyPaid);
    expect(presentation.payments.single.method, 'Transfer');
    expect(presentation.clientPhone, '+2348091234567');
  });
}

final _session = UserSession(
  user: AppUser(
    userId: 'admin-user',
    clinicId: 'clinic-1',
    fullName: 'Clinic Administrator',
    username: 'admin@example.com',
    email: 'admin@example.com',
    passwordHash: 'not-used',
    role: 'Clinic Administrator',
    accountType: AccountTypes.clinicAdministrator,
    permissions: '[]',
    invitationStatus: 'Accepted',
    requiresPasswordChange: false,
    twoFactorEnabled: false,
    accountStatus: 'Active',
    membershipStatus: 'Active',
    rememberMe: false,
    sessionTimeoutMinutes: 30,
    createdAt: DateTime(2026),
  ),
  clinic: Clinic(
    clinicId: 'clinic-1',
    clinicName: 'Avera Veterinary Clinic',
    clinicType: 'Veterinary Clinic',
    currency: 'NGN',
    timeZone: 'Africa/Lagos',
    preferredLanguage: 'English',
    themeColor: '#087F7B',
    dateRegistered: DateTime(2026),
    subscriptionPlan: 'Professional',
    clinicStatus: 'Active',
    patientNumberSequenceLength: 5,
    patientNumberResetYearly: true,
    patientNumberPrefixReviewed: true,
    address: 'Amawbia',
    city: 'Awka',
    state: 'Anambra',
    country: 'Nigeria',
    email: 'clinic@example.com',
    phoneNumber: '+2348000000000',
  ),
  backendPermissions: const {Permissions.billingView},
);
