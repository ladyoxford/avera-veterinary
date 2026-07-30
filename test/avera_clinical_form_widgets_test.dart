import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets(
      'shared clinical fields render at narrow width in ${theme.brightness.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final title = TextEditingController();
        addTearDown(title.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(
                  AveraSpacing.pageHorizontalPadding,
                ),
                children: [
                  AveraLabeledTextField(
                    label: 'Clinical notes',
                    controller: title,
                    hintText: 'Enter relevant clinical notes',
                    minLines: 3,
                    maxLines: 6,
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  AveraLabeledDropdownField<String>(
                    label: 'Priority',
                    hintText: 'Select priority',
                    value: 'Routine',
                    items: const [
                      DropdownMenuItem(
                        value: 'Routine',
                        child: Text('Routine'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: AveraSpacing.cardGap),
                  const AveraPrimaryActionButton(label: 'Create Prescription'),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('CLINICAL NOTES'), findsOneWidget);
        expect(find.text('PRIORITY'), findsOneWidget);
        expect(find.text('Create Prescription'), findsOneWidget);
        expect(theme.colorScheme.onPrimary, Colors.white);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
