import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';

void main() {
  Widget buildSubject({double textScale = 1}) => MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: ListView.separated(
          padding: const EdgeInsets.all(AveraSpacing.pageHorizontalPadding),
          itemCount: 2,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AveraSpacing.cardGap),
          itemBuilder: (_, index) => AveraAdministrationCard(
            icon: index == 0
                ? Icons.people_alt_outlined
                : Icons.admin_panel_settings_outlined,
            title: index == 0 ? 'Users' : 'Roles & Permissions',
            subtitle: index == 0
                ? 'Invite staff, manage roles, status and access.'
                : 'Configure role defaults and effective permissions for a clinic with a long name.',
          ),
        ),
      ),
    ),
  );

  testWidgets('administration cards have a visible shared gap', (tester) async {
    await tester.pumpWidget(buildSubject());

    final first = tester.getRect(find.text('Users'));
    final second = tester.getRect(find.text('Roles & Permissions'));

    expect(second.top - first.bottom, greaterThan(AveraSpacing.cardGap));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long administrative card text remains responsive', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(textScale: 1.5));

    expect(find.text('Roles & Permissions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
