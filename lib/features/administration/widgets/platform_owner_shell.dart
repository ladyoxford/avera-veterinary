import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_providers.dart';

class PlatformOwnerShell extends ConsumerWidget {
  const PlatformOwnerShell({super.key, required this.child});

  final Widget child;

  static const _destinations = <_PlatformDestination>[
    _PlatformDestination(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      path: '/platform',
    ),
    _PlatformDestination(
      label: 'Clinics',
      icon: Icons.local_hospital_outlined,
      selectedIcon: Icons.local_hospital_rounded,
      path: '/platform/clinics',
    ),
    _PlatformDestination(
      label: 'Subscriptions',
      icon: Icons.workspace_premium_outlined,
      selectedIcon: Icons.workspace_premium_rounded,
      path: '/platform/subscriptions',
    ),
    _PlatformDestination(
      label: 'Operations',
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings_rounded,
      path: '/platform/operations',
    ),
    _PlatformDestination(
      label: 'Account',
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle_rounded,
      path: '/platform/account',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(userSessionProvider).valueOrNull;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.isPlatformOwner) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/login'),
            child: const Text('Return to Sign In'),
          ),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final selectedIndex = _selectedIndex(GoRouterState.of(context).uri.path);
    void select(int index) {
      if (index != selectedIndex) context.go(_destinations[index].path);
    }

    if (width >= 840) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                extended: width >= 1180,
                selectedIndex: selectedIndex,
                onDestinationSelected: select,
                labelType: width >= 1180
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    final compactLabel = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      height: 1.1,
      letterSpacing: 0,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarTheme.of(context).copyWith(
          height: 72,
          labelTextStyle: WidgetStatePropertyAll(compactLabel),
        ),
      ),
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: select,
          destinations: [
            for (final destination in _destinations)
              NavigationDestination(
                icon: Icon(destination.icon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }

  int _selectedIndex(String path) {
    if (path == '/platform') return 0;
    if (path.startsWith('/platform/clinics')) return 1;
    if (path.startsWith('/platform/subscriptions') ||
        path.startsWith('/platform/revenue')) {
      return 2;
    }
    if (path.startsWith('/platform/account') ||
        path.startsWith('/platform/password')) {
      return 4;
    }
    return 3;
  }
}

class _PlatformDestination {
  const _PlatformDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}
