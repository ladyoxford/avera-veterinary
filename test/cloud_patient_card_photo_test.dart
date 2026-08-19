import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/remote/clinical_remote_data_source.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/animals/screens/cloud_patient_screens.dart';
import 'package:avera/features/shared/widgets/identity_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Registered Pets row passes the saved patient photo to its avatar',
    (tester) async {
      const photoUrl = 'https://storage.avera.test/patients/luna.jpg';
      await tester.pumpWidget(_subject(_patient(photoUrl: photoUrl)));
      await tester.pump();

      final avatar = tester.widget<AveraIdentityAvatar>(
        find.byKey(const Key('patient-avatar-patient-1')),
      );
      expect(avatar.photoReference, photoUrl);
      expect(avatar.size, 48);
    },
  );

  testWidgets(
    'Registered Pets row retains the initial fallback without a photo',
    (tester) async {
      await tester.pumpWidget(_subject(_patient()));
      await tester.pumpAndSettle();

      final avatar = tester.widget<AveraIdentityAvatar>(
        find.byKey(const Key('patient-avatar-patient-1')),
      );
      expect(avatar.photoReference, isNull);
      expect(find.text('L'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _subject(RemotePatient patient) => ProviderScope(
  overrides: [
    userSessionProvider.overrideWith(
      (ref) async =>
          throw StateError('No authenticated session in widget test.'),
    ),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: CloudPatientCard(patient: patient)),
  ),
);

RemotePatient _patient({String? photoUrl}) => RemotePatient(
  id: 'patient-1',
  hospitalNumber: 'AVR-2026-00001',
  name: 'Luna',
  species: 'Cat',
  breed: 'Domestic Shorthair',
  sex: 'Female',
  status: 'Active',
  ownerName: 'Ada Okafor',
  ownerPhone: '08010000000',
  photoUrl: photoUrl,
);
