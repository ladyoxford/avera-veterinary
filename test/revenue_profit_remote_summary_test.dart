import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
