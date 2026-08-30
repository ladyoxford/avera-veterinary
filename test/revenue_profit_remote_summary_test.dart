import 'dart:convert';

import 'package:avera/core/remote/api_client.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('remote revenue summary parses PostgreSQL numeric values', () {
    final summary = RemoteRevenueProfitSummary.fromJson({
      'revenue': '125000.50',
      'cost': '42000.25',
      'clinic_revenue': '80000.50',
      'farm_revenue': '45000',
      'transaction_count': '7',
      'missing_cost_lines': '2',
    });

    expect(summary.revenue, 125000.50);
    expect(summary.cost, 42000.25);
    expect(summary.clinicRevenue, 80000.50);
    expect(summary.farmRevenue, 45000);
    expect(summary.transactionCount, 7);
    expect(summary.missingCostLines, 2);
  });

  test('remote revenue summary safely defaults absent aggregates', () {
    final summary = RemoteRevenueProfitSummary.fromJson(const {});

    expect(summary.revenue, 0);
    expect(summary.cost, 0);
    expect(summary.clinicRevenue, 0);
    expect(summary.farmRevenue, 0);
    expect(summary.transactionCount, 0);
    expect(summary.missingCostLines, 0);
  });

  test('remote revenue drill-down preserves typed financial values', () {
    final page = RemoteRevenueDrilldownPage.fromJson({
      'items': [
        {
          'id': 'payment-1',
          'row_type': 'payment',
          'invoice_id': 'invoice-1',
          'invoice_number': 'INV-260830-ABC12345',
          'occurred_at': '2026-08-30T08:50:00.000Z',
          'client_name': 'Example Client',
          'context': 'Clinic',
          'amount': '5000.50',
        },
      ],
      'page': 1,
      'pageSize': 25,
      'total': 1,
      'hasNextPage': false,
      'totalValue': '5000.50',
    });

    expect(page.totalValue, 5000.50);
    expect(page.items.single.invoiceNumber, 'INV-260830-ABC12345');
    expect(page.items.single.amount, 5000.50);
  });

  test(
    'remote revenue request converts local boundaries to UTC instants',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'avera_access_token': 'access-token',
      });
      Uri? requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({
            'revenue': 0,
            'cost': 0,
            'clinic_revenue': 0,
            'farm_revenue': 0,
            'transaction_count': 0,
            'missing_cost_lines': 0,
          }),
          200,
        );
      });
      final source = ClinicalRemoteDataSource(
        ApiClient(
          baseUrl: 'https://api.avera.test',
          tokens: const TokenStore(FlutterSecureStorage()),
          client: client,
        ),
      );
      final from = DateTime(2026, 8, 1);
      final to = DateTime(2026, 9, 1);

      await source.revenueProfitSummary(period: '1m', from: from, to: to);

      expect(requestedUri!.path, '/api/v1/billing/revenue-summary');
      expect(requestedUri!.queryParameters['period'], '1m');
      expect(
        requestedUri!.queryParameters['from'],
        from.toUtc().toIso8601String(),
      );
      expect(requestedUri!.queryParameters['to'], to.toUtc().toIso8601String());
    },
  );
}
