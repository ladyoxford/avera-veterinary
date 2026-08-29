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

  test('version 27 preserves existing invoices and dependent lines', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE invoices ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'clinic_id TEXT NOT NULL, animal_id INTEGER NOT NULL, '
            'appointment_id INTEGER, consultation_id INTEGER, '
            'reference TEXT NOT NULL, '
            "status TEXT NOT NULL DEFAULT 'Pending', "
            "context_type TEXT NOT NULL DEFAULT 'clinic_visit', "
            'products_subtotal REAL NOT NULL DEFAULT 0, '
            'services_subtotal REAL NOT NULL DEFAULT 0, '
            'consultation_fee REAL NOT NULL DEFAULT 0, '
            'home_service_fee REAL NOT NULL DEFAULT 0, '
            'total REAL NOT NULL DEFAULT 0, '
            'amount_paid REAL NOT NULL DEFAULT 0, '
            'refund_total REAL NOT NULL DEFAULT 0, '
            'balance REAL NOT NULL DEFAULT 0, payment_method TEXT, '
            'linked_clinical_operation_id INTEGER, paid_at INTEGER, '
            'paid_by_user_id TEXT, voided_at INTEGER, '
            'voided_by_user_id TEXT, void_reason TEXT, '
            'clinic_name_snapshot TEXT NOT NULL, '
            'clinic_address_snapshot TEXT, clinic_phone_snapshot TEXT, '
            'clinic_email_snapshot TEXT, created_by_user_id TEXT NOT NULL, '
            'created_at INTEGER NOT NULL, updated_at INTEGER)',
          );
          sqlite.execute(
            'CREATE TABLE invoice_service_lines ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'invoice_id INTEGER NOT NULL REFERENCES invoices(id), '
            'animal_id INTEGER, description TEXT NOT NULL, '
            'amount REAL NOT NULL, cost_snapshot REAL)',
          );
          sqlite.execute(
            "INSERT INTO invoices (id, clinic_id, animal_id, reference, "
            "total, balance, clinic_name_snapshot, created_by_user_id, "
            "created_at) VALUES (1, 'clinic-a', 42, 'INV-1', 5000, 5000, "
            "'Clinic A', 'user-a', 1)",
          );
          sqlite.execute(
            "INSERT INTO invoice_service_lines "
            "(id, invoice_id, animal_id, description, amount) "
            "VALUES (1, 1, 42, 'Consultation', 5000)",
          );
          sqlite.execute('PRAGMA user_version = 26');
        },
      ),
    );
    addTearDown(database.close);

    final invoice = await database
        .customSelect(
          'SELECT reference, animal_id, farm_id FROM invoices WHERE id = 1',
        )
        .getSingle();
    final line = await database
        .customSelect(
          'SELECT invoice_id, description FROM invoice_service_lines WHERE id = 1',
        )
        .getSingle();

    expect(invoice.read<String>('reference'), 'INV-1');
    expect(invoice.read<int>('animal_id'), 42);
    expect(invoice.readNullable<String>('farm_id'), isNull);
    expect(line.read<int>('invoice_id'), 1);
    expect(line.read<String>('description'), 'Consultation');
  });

  test('version 33 restores billable inventory category records', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute(
            'CREATE TABLE inventory_items ('
            'id INTEGER PRIMARY KEY, category TEXT NOT NULL, '
            'category_id TEXT, is_sellable INTEGER NOT NULL)',
          );
          sqlite.execute(
            "INSERT INTO inventory_items VALUES "
            "(1, 'Medical Equipment & Instruments', 'medical_equipment', 0), "
            "(2, 'Office & Administrative Supplies', 'office_admin', 0), "
            "(3, 'Medicines / Drugs', 'drugs', 0)",
          );
          sqlite.execute('PRAGMA user_version = 32');
        },
      ),
    );
    addTearDown(database.close);

    final rows = await database
        .customSelect('SELECT id, is_sellable FROM inventory_items ORDER BY id')
        .get();

    expect(rows.map((row) => row.read<int>('is_sellable')), [1, 1, 0]);
  });
}
