import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/services/hospital_numbering.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/animals/screens/animal_registration_screen.dart';

void main() {
  test(
    'backend registration photo is uploaded against the created patient id',
    () async {
      String? uploadedPatientId;
      String? uploadedContentType;
      String? uploadedData;
      final result = await uploadRegisteredPatientPhoto(
        photo: XFile.fromData(Uint8List.fromList([1, 2, 3])),
        patientId: 'patient-uuid',
        upload:
            ({
              required patientId,
              required contentType,
              required base64Data,
            }) async {
              uploadedPatientId = patientId;
              uploadedContentType = contentType;
              uploadedData = base64Data;
            },
      );

      expect(result, isTrue);
      expect(uploadedPatientId, 'patient-uuid');
      expect(uploadedContentType, 'image/jpeg');
      expect(uploadedData, base64Encode([1, 2, 3]));
    },
  );

  test('oversized registration photo is rejected before upload', () async {
    var uploadCalled = false;
    final result = await uploadRegisteredPatientPhoto(
      photo: XFile.fromData(Uint8List(1024 * 1024 + 1)),
      patientId: 'patient-uuid',
      upload:
          ({
            required patientId,
            required contentType,
            required base64Data,
          }) async {
            uploadCalled = true;
          },
    );

    expect(result, isFalse);
    expect(uploadCalled, isFalse);
  });

  testWidgets('species controls searchable compatible breed selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalNumberPreviewProvider.overrideWith(
            (ref) async => const HospitalNumberPreview(
              clinicId: 'demo-clinic',
              prefix: 'AVR',
              year: 2026,
              sequence: 1,
              sequenceLength: 5,
              prefixRequiresReview: false,
            ),
          ),
          userSessionProvider.overrideWith(
            (ref) => Future.error(StateError('Not required for this test')),
          ),
          animalAgeReferenceDateProvider.overrideWith(
            (ref) => DateTime(2026, 7, 30),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AnimalRegistrationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final speciesField = find.byKey(const Key('species-selection-field'));
    expect(tester.getSize(speciesField).width, greaterThan(740));
    expect(find.text('Select a species first'), findsOneWidget);

    await tester.tap(speciesField);
    await tester.pumpAndSettle();
    expect(find.text('Select Species'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('catalogue-search-field')),
      'Dog',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-option-species_dog')));
    await tester.pumpAndSettle();

    expect(find.text('Dog - Canine'), findsOneWidget);
    await tester.tap(find.byKey(const Key('breed-selection-field')));
    await tester.pumpAndSettle();
    expect(find.text('Select Dog Breed'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('catalogue-search-field')),
      'Lhasa Apso',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('catalogue-option-breed_dog_lhasa_apso')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('catalogue-option-breed_dog_lhasa_apso')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lhasa Apso'), findsOneWidget);

    await tester.tap(speciesField);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalogue-search-field')),
      'Cat',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalogue-option-species_cat')));
    await tester.pumpAndSettle();

    expect(find.text('Cat - Feline'), findsOneWidget);
    expect(find.text('Lhasa Apso'), findsNothing);
    expect(find.text('Select Breed'), findsOneWidget);
  });

  testWidgets('current age produces a live estimated birth-date preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalNumberPreviewProvider.overrideWith(
            (ref) async => const HospitalNumberPreview(
              clinicId: 'demo-clinic',
              prefix: 'AVR',
              year: 2026,
              sequence: 1,
              sequenceLength: 5,
              prefixRequiresReview: false,
            ),
          ),
          userSessionProvider.overrideWith(
            (ref) => Future.error(StateError('Not required for this test')),
          ),
          animalAgeReferenceDateProvider.overrideWith(
            (ref) => DateTime(2026, 7, 30),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AnimalRegistrationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    final currentAgeField = find
        .widgetWithText(TextFormField, 'Enter current age')
        .hitTestable()
        .first;
    expect(find.text('Date of Birth'), findsOneWidget);
    expect(find.text('Current Age'), findsOneWidget);
    expect(find.text('Weeks'), findsOneWidget);

    await tester.enterText(currentAgeField, '6');
    await tester.pump();

    expect(find.text('Estimated date of birth: June 18, 2026'), findsOneWidget);
    expect(find.text('Current age: 6 weeks'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration screen renders in dark theme without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hospitalNumberPreviewProvider.overrideWith(
            (ref) async => const HospitalNumberPreview(
              clinicId: 'demo-clinic',
              prefix: 'AVR',
              year: 2026,
              sequence: 1,
              sequenceLength: 5,
              prefixRequiresReview: false,
            ),
          ),
          userSessionProvider.overrideWith(
            (ref) => Future.error(StateError('Not required for this test')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const AnimalRegistrationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AVR-2026-00001'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
