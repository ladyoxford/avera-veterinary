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
}
