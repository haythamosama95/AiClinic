import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';

/// Shared navigation shell for authenticated routes.
///
/// Provides a [NavigationRail] for lateral navigation between top-level
/// feature areas (Home, Patients, Appointments, Billing, Settings). Each child route keeps its own
/// [Scaffold] and [AppBar] for page-specific actions.
class AuthenticatedShell extends ConsumerWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  static const _destinations = <_NavDestination>[
    _NavDestination(route: AppRoutes.home, icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
    _NavDestination(
      route: AppRoutes.patients,
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      label: 'Patients',
      permissionKey: 'patients.view',
    ),
    _NavDestination(
      route: AppRoutes.appointments,
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
      label: 'Appointments',
      anyPermissionKeys: [PermissionKeys.appointmentsCreate, PermissionKeys.appointmentsCancel],
    ),
    _NavDestination(
      route: AppRoutes.billingInvoices,
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      label: 'Billing',
      permissionKey: PermissionKeys.invoicesView,
    ),
    _NavDestination(
      route: AppRoutes.settings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final auth = session.context;

    if (auth == null || auth.setupRequired) {
      return child;
    }

    final visibleDestinations = _destinations.where((d) {
      if (d.anyPermissionKeys != null) {
        return d.anyPermissionKeys!.any(auth.permissions.contains);
      }
      if (d.permissionKey == null) {
        return true;
      }
      return auth.permissions.contains(d.permissionKey);
    }).toList();

    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _resolveIndex(currentPath, visibleDestinations);

    return Row(
      children: [
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            if (index >= 0 && index < visibleDestinations.length) {
              context.go(visibleDestinations[index].route);
            }
          },
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (final dest in visibleDestinations)
              NavigationRailDestination(
                icon: Icon(dest.icon),
                selectedIcon: Icon(dest.selectedIcon),
                label: Text(dest.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: child),
      ],
    );
  }

  static int _resolveIndex(String path, List<_NavDestination> destinations) {
    for (var i = 0; i < destinations.length; i++) {
      final route = destinations[i].route;
      if (path == route || (route != AppRoutes.home && path.startsWith(route))) {
        return i;
      }
    }
    return 0;
  }
}

class _NavDestination {
  const _NavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.permissionKey,
    this.anyPermissionKeys,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? permissionKey;
  final List<String>? anyPermissionKeys;
}
