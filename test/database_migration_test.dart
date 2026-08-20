import 'package:avera/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('version 23 invoice backfill treats Paid as a text value', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE invoices ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'clinic_id TEXT NOT NULL, '
            'reference TEXT NOT NULL, '
            'status TEXT NOT NULL, '
            'total REAL NOT NULL, '
            'created_at INTEGER NOT NULL)',
          );
          sqlite.execute(
            "INSERT INTO invoices "
            "(clinic_id, reference, status, total, created_at) VALUES "
            "('clinic-a', 'INV-PAID', 'Paid', 125, 1), "
            "('clinic-a', 'INV-PENDING', 'Pending', 80, 2)",
          );
          sqlite.execute('PRAGMA user_version = 22');
        },
      ),
    );
    addTearDown(database.close);

    final rows = await database
        .customSelect(
          'SELECT reference, amount_paid, balance FROM invoices '
          'ORDER BY reference',
        )
        .get();
    final values = {
      for (final row in rows)
        row.read<String>('reference'): (
          amountPaid: row.read<double>('amount_paid'),
          balance: row.read<double>('balance'),
        ),
    };

    expect(values['INV-PAID']?.amountPaid, 125);
    expect(values['INV-PAID']?.balance, 0);
    expect(values['INV-PENDING']?.amountPaid, 0);
    expect(values['INV-PENDING']?.balance, 80);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      AppDatabase.currentSchemaVersion,
    );
  });

  test(
    'version 24 derives an estimated birth date from legacy year age',
    () async {
      final registered = DateTime(2026, 7, 30);
      final database = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              'CREATE TABLE animals ('
              'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              'clinic_id TEXT NOT NULL, hospital_number TEXT NOT NULL, '
              'animal_name TEXT NOT NULL, species TEXT NOT NULL, '
              'breed TEXT, sex TEXT, age INTEGER, date_of_birth INTEGER, '
              'weight REAL, color TEXT, microchip_number TEXT, '
              'owner_id INTEGER NOT NULL, photo TEXT, '
              'date_registered INTEGER NOT NULL, notes TEXT, '
              "status TEXT NOT NULL DEFAULT 'Active', "
              'status_updated_at INTEGER, status_updated_by TEXT, '
              "number_assignment_status TEXT NOT NULL DEFAULT 'Legacy', "
              'temporary_hospital_number TEXT, registration_year INTEGER, '
              'registration_submission_id TEXT)',
            );
            sqlite.execute(
              'INSERT INTO animals '
              '(clinic_id, hospital_number, animal_name, species, age, '
              'owner_id, date_registered) VALUES '
              "('clinic-a', 'LEG-1', 'Legacy', 'Dog', 3, 1, "
              '${registered.millisecondsSinceEpoch ~/ 1000})',
            );
            sqlite.execute('PRAGMA user_version = 23');
          },
        ),
      );
      addTearDown(database.close);

      final animal = await database.select(database.animals).getSingle();
      expect(animal.dateOfBirth, DateTime(2023, 7, 30));
      expect(animal.isDateOfBirthEstimated, isTrue);
      expect(animal.originalAgeValue, 3);
      expect(animal.originalAgeUnit, 'years');
      expect(animal.ageRecordedAt, registered);
      expect(animal.age, 3);
    },
  );

  test('version 25 preserves invoice lines and attributes legacy lines', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE invoices (id INTEGER PRIMARY KEY, animal_id INTEGER NOT NULL)',
          );
          sqlite.execute(
            'CREATE TABLE invoice_product_lines ('
            'id INTEGER PRIMARY KEY, invoice_id INTEGER NOT NULL, '
            'inventory_item_id INTEGER NOT NULL, product_name_snapshot TEXT NOT NULL, '
            'category_name_snapshot TEXT NOT NULL, batch_number_snapshot TEXT, '
            'quantity INTEGER NOT NULL, unit_price REAL NOT NULL, line_total REAL NOT NULL)',
          );
          sqlite.execute(
            'CREATE TABLE invoice_service_lines ('
            'id INTEGER PRIMARY KEY, invoice_id INTEGER NOT NULL, '
            'description TEXT NOT NULL, amount REAL NOT NULL)',
          );
          sqlite.execute('INSERT INTO invoices VALUES (1, 42)');
          sqlite.execute(
            "INSERT INTO invoice_service_lines VALUES (1, 1, 'Consultation', 5000)",
          );
          sqlite.execute('PRAGMA user_version = 24');
        },
      ),
    );
    addTearDown(database.close);

    final line = await database
        .customSelect(
          'SELECT description, animal_id FROM invoice_service_lines',
        )
        .getSingle();
    expect(line.read<String>('description'), 'Consultation');
    expect(line.read<int>('animal_id'), 42);
  });
}
