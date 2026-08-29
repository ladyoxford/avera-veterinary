import 'package:avera/core/config/app_providers.dart';
import 'package:avera/core/theme/app_theme.dart';
import 'package:avera/features/billing/screens/revenue_profit_screen.dart';
import 'package:avera/features/farm/widgets/farm_back_navigation.dart';
import 'package:avera/features/shared/widgets/app_scaffold.dart';
import 'package:avera/features/shared/widgets/avera_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('workspace routes map to the intended permanent navigation root', () {
    expect(mobileNavigationIndex('/dashboard'), 0);
    expect(mobileNavigationIndex('/inventory'), 0);
    expect(mobileNavigationIndex('/billing/history'), 0);
    expect(mobileNavigationIndex('/revenue'), 0);
    expect(mobileNavigationIndex('/animals/animal-1'), 1);
    expect(mobileNavigationIndex('/consultations/new'), 2);
    expect(mobileNavigationIndex('/appointments'), 3);
    expect(mobileNavigationIndex('/more'), 4);
  });

  test('dark workspace foundation is limited to the upgraded modules', () {
    expect(usesAveraDarkCoreFoundation('/animals'), isTrue);
    expect(usesAveraDarkCoreFoundation('/inventory'), isTrue);
    expect(usesAveraDarkCoreFoundation('/billing/history'), isTrue);
    expect(usesAveraDarkCoreFoundation('/revenue'), isTrue);
    expect(usesAveraDarkCoreFoundation('/settings'), isFalse);
  });

  testWidgets('permanent mobile navigation uses stable visible glyphs', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/inventory',
      routes: [
        for (final path in [
          '/dashboard',
          '/animals',
          '/consultations/new',
          '/appointments',
          '/more',
          '/inventory',
        ])
          GoRoute(
            path: path,
            builder: (context, state) =>
                const AppScaffold(child: ColoredBox(color: Colors.transparent)),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userSessionProvider.overrideWith(
            (ref) async => throw StateError('No session required by this test'),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<NavigationBar>(
      find.byKey(const Key('shared-mobile-navigation')),
    );
    expect(bar.selectedIndex, 0);
    const expected = {
      'dashboard': Icons.dashboard,
      'patients': Icons.pets,
      'consult': Icons.local_hospital,
      'schedule': Icons.event,
      'more': Icons.menu,
    };
    for (final entry in expected.entries) {
      final icons = find.byKey(
        Key(
          entry.key == 'dashboard'
              ? 'app-nav-selected-icon-${entry.key}'
              : 'app-nav-icon-${entry.key}',
        ),
      );
      expect(icons, findsOneWidget);
      expect(tester.widget<Icon>(icons).icon, entry.value);
    }

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/more');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AVERA dark wrapper supplies dark theme to descendants', (
    tester,
  ) async {
    Brightness? brightness;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AveraDarkTheme(
          child: Builder(
            builder: (context) {
              brightness = Theme.of(context).brightness;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(brightness, Brightness.dark);
  });

  testWidgets('farm system back falls back to More instead of exiting', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/farm-records',
      routes: [
        GoRoute(
          path: '/more',
          builder: (context, state) => const Scaffold(body: Text('More')),
        ),
        GoRoute(
          path: '/farm-records',
          builder: (context, state) => const FarmBackNavigationScope(
            fallbackPath: '/more',
            child: Scaffold(body: Text('Farm Records')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Farm Records'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/more');
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'missing historical costs explicitly warn that profit is overstated',
    () {
      final message = missingHistoricalCostWarning(11);
      expect(message, contains('11 invoice line(s)'));
      expect(message, contains('Profit may be overstated'));
      expect(message, isNot(contains('Profit excludes')));
    },
  );
}
