import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../repositories/clinic_repository.dart';

class ClinicDocumentBranding {
  const ClinicDocumentBranding({
    required this.clinicName,
    required this.currency,
    this.address,
    this.phone,
    this.email,
    this.logoReference,
    this.accentHex = '#087F7B',
  });

  factory ClinicDocumentBranding.fromSession(UserSession session) {
    final clinic = session.clinic;
    final addressParts = <String>{
      for (final value in [
        clinic.address,
        clinic.city,
        clinic.state,
        clinic.country,
      ])
        if (value?.trim().isNotEmpty == true) value!.trim(),
    };
    return ClinicDocumentBranding(
      clinicName: clinic.clinicName,
      currency: clinic.currency,
      address: addressParts.isEmpty ? null : addressParts.join(', '),
      phone: clinic.phoneNumber,
      email: clinic.email,
      logoReference: clinic.logo,
      accentHex: clinic.themeColor,
    );
  }

  final String clinicName;
  final String currency;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoReference;
  final String accentHex;
}

class ClinicDocumentBrandingService {
  const ClinicDocumentBrandingService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<pw.MemoryImage?> loadLogo(String? reference) async {
    if (!_present(reference)) return null;
    final value = reference!.trim();
    if (value.startsWith(RegExp(r'https?://'))) {
      final client = _client ?? http.Client();
      try {
        final response = await client.get(Uri.parse(value));
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.isNotEmpty) {
          return pw.MemoryImage(response.bodyBytes);
        }
      } catch (_) {
        return null;
      } finally {
        if (_client == null) client.close();
      }
      return null;
    }
    try {
      final file = File(value);
      if (await file.exists()) return pw.MemoryImage(await file.readAsBytes());
    } catch (_) {
      return null;
    }
    return null;
  }

  PdfColor accentColor(ClinicDocumentBranding branding) {
    try {
      return PdfColor.fromHex(branding.accentHex);
    } catch (_) {
      return PdfColor.fromHex('#087F7B');
    }
  }

  pw.Widget identity({
    required ClinicDocumentBranding branding,
    required pw.MemoryImage? logo,
    double logoSize = 46,
  }) {
    final accent = accentColor(branding);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: logoSize,
          height: logoSize,
          decoration: pw.BoxDecoration(
            color: logo == null ? accent : null,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          alignment: pw.Alignment.center,
          child: logo == null
              ? pw.Text(
                  _initials(branding.clinicName),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                )
              : pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                branding.clinicName,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (_present(branding.address)) pw.Text(branding.address!),
              pw.Wrap(
                spacing: 8,
                children: [
                  if (_present(branding.phone)) pw.Text(branding.phone!),
                  if (_present(branding.email)) pw.Text(branding.email!),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _present(String? value) => value?.trim().isNotEmpty == true;

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final initials = parts.map((part) => part[0].toUpperCase()).join();
    return initials.isEmpty ? 'AV' : initials;
  }
}
