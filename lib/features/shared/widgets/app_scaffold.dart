import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_providers.dart';
import '../../../core/security/access_control.dart';
import 'avera_logo.dart';

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    final offline = ref.watch(offlineAuthorizationSnapshotProvider);
    final mobileDestinations = <_Destination>[
      const _Destination('Dashboard', Icons.dashboard, '/dashboard'),
      const _Destination('Patients', Icons.pets, '/animals'),
      const _Destination('Consult', Icons.local_hospital, '/consultations/new'),
      const _Destination('Schedule', Icons.event, '/appointments'),
      const _Destination('More', Icons.menu, '/more'),
    ];
    final destinations = <_Destination>[
      const _Destination('Dashboard', Iconsax.category, '/dashboard'),
      const _Destination('Animals', Iconsax.search_normal, '/animals'),
      if (session?.can(Permissions.patientsCreate) ?? true)
        const _Destination('Register', Iconsax.add_square, '/animals/new'),
      if (session?.can(Permissions.consultationsCreate) ?? true)
        const _Destination('Consult', Iconsax.note_text, '/consultations/new'),
      const _Destination('Schedule', Iconsax.calendar, '/appointments'),
      const _Destination('More', Icons.apps_rounded, '/more'),
      const _Destination('Vaccines', Iconsax.shield_tick, '/vaccinations'),
      const _Destination(
        'Notifications',
        Iconsax.notification,
        '/notifications',
      ),
      const _Destination('Inventory', Iconsax.box, '/inventory'),
      const _Destination('Billing', Iconsax.receipt_item, '/billing'),
      const _Destination('Reports', Iconsax.document_download, '/reports'),
      if (session?.can(Permissions.usersView) ?? false)
        const _Destination(
          'Administration',
          Iconsax.security_user,
          '/administration',
        ),
      const _Destination('Settings', Iconsax.setting_2, '/settings'),
      const _Destination('Backup', Iconsax.archive_book, '/backup'),
    ];
    final width = MediaQuery.sizeOf(context).width;
    final location = GoRouterState.of(context).uri.toString();
    final selected = destinations
        .indexWhere((d) {
          if (d.path == '/dashboard') return location == '/dashboard';
          return location.startsWith(d.path);
        })
        .clamp(0, destinations.length - 1);

    if (width >= 900) {
      final scaffold = Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: width >= 1200,
              leading: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 20),
                child: width >= 1200
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AveraCompactLogo(size: 48),
                          SizedBox(height: 8),
                          Text('AVERA'),
                          SizedBox(height: 2),
                          Text(
                            'Veterinary Practice Management',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : const AveraCompactLogo(size: 44),
              ),
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  context.go(destinations[index].path),
              labelType: width >= 1200
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _WorkspaceBody(offline: offline != null, child: child),
            ),
          ],
        ),
      );
      return scaffold;
    }

    final mobileSelected = mobileNavigationIndex(location);

    final navigationBar = NavigationBar(
      key: const Key('shared-mobile-navigation'),
      selectedIndex: mobileSelected,
      onDestinationSelected: (index) =>
          context.go(mobileDestinations[index].path),
      destinations: [
        for (final destination in mobileDestinations)
          NavigationDestination(
            icon: Icon(
              destination.icon,
              key: Key('app-nav-icon-${destination.label.toLowerCase()}'),
            ),
            selectedIcon: Icon(
              destination.icon,
              key: Key(
                'app-nav-selected-icon-${destination.label.toLowerCase()}',
              ),
            ),
            label: destination.label,
          ),
      ],
    );

    final scaffold = Scaffold(
      body: _WorkspaceBody(offline: offline != null, child: child),
      bottomNavigationBar: navigationBar,
    );
    return scaffold;
  }
}

int mobileNavigationIndex(String location) {
  if (location == '/dashboard' ||
      location.startsWith('/inventory') ||
      location.startsWith('/billing') ||
      location.startsWith('/revenue')) {
    return 0;
  }
  if (location.startsWith('/animals')) return 1;
  if (location.startsWith('/consultations')) return 2;
  if (location.startsWith('/appointments')) return 3;
  return 4;
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.child, required this.offline});
  final Widget child;
  final bool offline;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (offline)
        Material(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: const SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OFFLINE - Changes will sync when AVERA securely reconnects.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      Expanded(child: child),
    ],
  );
}

class _Destination {
  const _Destination(this.label, this.icon, this.path);

  final String label;
  final IconData icon;
  final String path;
}
