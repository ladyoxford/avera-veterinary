import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/bioqarah_receipt_importer.dart';

void main() {
  test('Bioqarah invoice 300519 receives base stock once', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    await BioqarahReceiptImporter(database).importFor(session!);

    final optimax =
        await (database.select(database.inventoryItems)..where(
              (item) => item.drugName.equals('Optimax ALS Dog Canned Food'),
            ))
            .getSingle();
    final booster =
        await (database.select(database.inventoryItems)..where(
              (item) => item.drugName.equals('Booster Pate Puppy Canned Food'),
            ))
            .getSingle();
    final chewy =
        await (database.select(database.inventoryItems)..where(
              (item) => item.drugName.equals('Chewy Pet Adult Canned Food'),
            ))
            .getSingle();
    expect(optimax.quantity, 72);
    expect(booster.quantity, 72);
    expect(chewy.quantity, 72);
    expect(chewy.isSellable, isFalse);
    expect(optimax.buyingPrice, closeTo(1516.6667, 0.001));
    expect(
      (await database.select(database.inventoryStockMovements).get())
          .where((movement) => movement.movementType == 'Receipt')
          .length,
      17,
    );
    await expectLater(
      BioqarahReceiptImporter(database).importFor(session),
      throwsA(isA<StateError>()),
    );
  });
}
