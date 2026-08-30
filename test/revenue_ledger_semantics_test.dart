import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/hospital_numbering.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local signed-ledger and cost allocation cover refund edge cases', () {
    expect(
      signedRevenueLedgerAmount(transactionType: 'Payment', amount: 100),
      100,
    );
    expect(
      signedRevenueLedgerAmount(transactionType: 'Refund', amount: 25),
      -25,
    );

    double allocation(double net) => allocateRevenueCost(
      recordedCost: 40,
      netSignedAmount: net,
      invoiceTotal: 100,
    );

    expect(allocation(100), 40, reason: 'payment only');
    expect(allocation(40), 16, reason: 'partial payment');
    expect(allocation(70), 28, reason: 'multiple payments');
    expect(allocation(50), 20, reason: 'payment plus partial refund');
    expect(allocation(0), 0, reason: 'full refund in the same period');
    expect(allocation(-25), -10, reason: 'refund in a later period');
    expect(allocation(130), 40, reason: 'cost never exceeds full invoice cost');
  });

  test(
    'offline report reverses revenue and cost in the refund period',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(
        database,
        clock: _FixedClock(DateTime(2026, 9, 10, 12)),
      );
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final patient = (await database.select(database.animals).get()).first;
      final item = (await database.select(database.inventoryItems).get()).first;
      await (database.update(
        database.inventoryItems,
      )..where((row) => row.id.equals(item.id))).write(
        const InventoryItemsCompanion(
          buyingPrice: Value(40),
          sellingPrice: Value(100),
        ),
      );
      final draft = await repository.saveInvoiceDraft(
        session: session,
        animalId: patient.id,
        products: [InvoiceProductDraft(inventoryItemId: item.id, quantity: 1)],
        services: const [],
        consultationFee: 0,
        homeServiceFee: 0,
      );
      await repository.issueInvoice(
        session: session,
        invoiceId: draft.invoice.id,
      );
      await repository.recordInvoicePayment(
        session: session,
        invoiceId: draft.invoice.id,
        amount: 40,
        paymentMethod: 'Cash',
        paidAt: DateTime(2026, 8, 5, 9),
      );
      await repository.recordInvoicePayment(
        session: session,
        invoiceId: draft.invoice.id,
        amount: 30,
        paymentMethod: 'Transfer',
        paidAt: DateTime(2026, 8, 20, 15),
      );
      await repository.refundInvoicePayment(
        session: session,
        invoiceId: draft.invoice.id,
        amount: 20,
        reason: 'Partial reversal',
      );

      final august = await repository.getRevenueProfitSummary(
        session: session,
        from: DateTime(2026, 8),
        to: DateTime(2026, 9),
      );
      expect(august.revenue, 70);
      expect(august.clinicRevenue, 70);
      expect(august.farmRevenue, 0);
      expect(august.transactionCount, 2);
      expect(august.cost, 28);
      expect(august.profit, 42);

      final september = await repository.getRevenueProfitSummary(
        session: session,
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
      );
      expect(september.revenue, -20);
      expect(september.clinicRevenue, -20);
      expect(september.transactionCount, 1);
      expect(september.cost, -8);
      expect(september.profit, -12);

      final allTime = await repository.getRevenueProfitSummary(
        session: session,
      );
      expect(allTime.revenue, 50);
      expect(allTime.cost, 20);
      expect(allTime.profit, 30);
      expect(allTime.transactionCount, 3);
    },
  );
}

class _FixedClock implements AppClock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowForClinic(Clinic clinic) => now;
}
