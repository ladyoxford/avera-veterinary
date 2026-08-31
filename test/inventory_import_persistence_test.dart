import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'import-style missing cost remains missing on the invoice snapshot',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ClinicRepository(database);
      await repository.seedSampleData();
      final session = (await repository.authenticateUser(
        username: 'admin@avera.test',
        password: 'admin123',
      ))!;
      final patient = (await database.select(database.animals).get()).first;

      final itemId = await repository.saveInventoryItem(
        session: session,
        name: 'Imported Collar',
        categoryId: 'pet_accessories',
        quantity: 4,
        minimumQuantity: 1,
        sellingPrice: 2500,
        buyingPrice: null,
        baseUnitLabel: 'piece',
      );
      final draft = await repository.saveInvoiceDraft(
        session: session,
        animalId: patient.id,
        products: [InvoiceProductDraft(inventoryItemId: itemId, quantity: 1)],
        services: const [],
        consultationFee: 0,
        homeServiceFee: 0,
      );
      final line = await (database.select(
        database.invoiceProductLines,
      )..where((row) => row.invoiceId.equals(draft.invoice.id))).getSingle();

      expect(line.unitCostSnapshot, isNull);
    },
  );
}
