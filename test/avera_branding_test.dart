import 'dart:io';

import 'package:avera/core/branding/avera_brand_assets.dart';
import 'package:avera/features/shared/widgets/avera_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AVERA logo uses the centralized teal asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AveraLogo(size: 80))),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AveraBrandAssets.primaryLogo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact dashboard brand uses the teal compact asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AveraBrandHeader(clinicName: 'Example Veterinary Clinic'),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AveraBrandAssets.compactLogo);
    expect(find.text('AVERA'), findsOneWidget);
    expect(find.text('Example Veterinary Clinic'), findsOneWidget);
  });

  testWidgets('missing logo asset renders a safe fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AveraLogo(
            size: 80,
            assetPathOverride: 'assets/branding/missing-logo.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teal logo renders in light and dark themes', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: AveraLogo(size: 80)),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('production sources do not reference retired blue logo paths', () {
    final retiredPaths = <String>[
      'assets/branding/avera_logo'
          '.svg',
      'assets/branding/avera_logo'
          '.png',
      'assets/branding/avera_official'
          '.png',
      'assets/images/logo'
          '.png',
    ];
    final files = <File>[
      File('pubspec.yaml'),
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('android')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.xml') ||
                file.path.endsWith('.gradle') ||
                file.path.endsWith('.kts'),
          ),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final retiredPath in retiredPaths) {
        expect(source, isNot(contains(retiredPath)), reason: file.path);
      }
    }
  });

  test('notification initialization uses the monochrome Android resource', () {
    final source = File(
      'lib/core/services/appointment_notification_service.dart',
    ).readAsStringSync();
    expect(source, contains("AndroidInitializationSettings('ic_stat_avera')"));
    expect(
      File('android/app/src/main/res/drawable/ic_stat_avera.xml').existsSync(),
      isTrue,
    );
  });
}
