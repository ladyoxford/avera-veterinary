import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/database/app_database.dart';
import 'package:avera/core/repositories/clinic_repository.dart';
import 'package:avera/core/services/clinic_document_branding.dart';
import 'package:avera/features/farm/services/farm_report_service.dart';

void main() {
  test('daily farm report produces a populated PDF', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = ClinicRepository(database);
    await repository.seedSampleData();
    final session = await repository.authenticateUser(
      username: 'admin@avera.test',
      password: 'admin123',
    );
    expect(session, isNot(equals(null)));

    final farm = await repository.createFarm(
      session: session!,
      name: 'Udeogalanya Farm',
      location: 'Ogidi, Anambra State',
      speciesIds: const ['species_cattle', 'species_goat'],
      breedIds: const [],
    );
    await repository.createFarmUnit(
      session: session,
      farmId: farm.id,
      name: 'PEN 1',
      unitType: 'Paddock',
      speciesId: 'species_cattle',
      maleCount: 2,
      femaleCount: 10,
    );
    final record = await repository.saveFarmDailyRecord(
      session: session,
      farmId: farm.id,
      recordDate: DateTime(2026, 7, 26),
      openingPopulation: 14,
      mortality: 1,
      feedSuppliedKg: 50,
      dailyNote: 'Routine checks completed. Water trough cleaned.',
      speciesMovements: const [
        FarmSpeciesMovementInput(
          speciesId: 'species_cattle',
          openingPopulation: 12,
        ),
        FarmSpeciesMovementInput(
          speciesId: 'species_goat',
          openingPopulation: 2,
          mortality: 1,
        ),
      ],
      finalize: true,
    );
    final detail = await repository.getFarmDailyRecordDetail(
      farmId: farm.id,
      recordId: record.id,
    );
    expect(detail, isNot(equals(null)));

    final bytes = await const FarmReportService().buildDailyRecordPdf(
      detail: detail!,
      preparedBy: session.user.fullName,
      branding: ClinicDocumentBranding.fromSession(session),
    );
    expect(bytes.length, greaterThan(3000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');

    final output = Directory('output/pdf');
    await output.create(recursive: true);
    await File(
      '${output.path}/avera-farm-daily-record-sample.pdf',
    ).writeAsBytes(bytes, flush: true);
  });
}
