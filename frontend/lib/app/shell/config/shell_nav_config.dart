import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Whether a nav item is visible for the current session permissions.
typedef ShellNavPermissionPredicate = bool Function(PermissionService permissions);

/// Static clinic navigation tree and route bindings for the authenticated shell.
///
/// Mirrors the web `nav-model.ts` groups, keyed to [AppRoutes] and gated by
/// [PermissionService] (items are hidden when the predicate returns false).
abstract final class ShellNavConfig {
  ShellNavConfig._();

  static const homeId = 'home';
  static const dashboardId = 'dashboard';
  static const patientsId = 'patients';
  static const appointmentsId = 'appointments';
  static const queueNavItemId = 'appointments-queue';
  static const encountersId = 'encounters';
  static const workspaceId = 'workspace';
  static const billingId = 'billing';
  static const invoicesId = 'invoices';
  static const servicesId = 'services';
  static const staffId = 'staff';
  static const shiftsId = 'shifts';
  static const reportsId = 'reports';
  static const settingsId = 'settings';

  static const Map<String, String> _routesByItemId = {
    homeId: AppRoutes.home,
    dashboardId: AppRoutes.home,
    patientsId: AppRoutes.patients,
    appointmentsId: AppRoutes.appointments,
    queueNavItemId: AppRoutes.appointmentsQueue,
    billingId: AppRoutes.settingsBilling,
    invoicesId: AppRoutes.billingInvoices,
    servicesId: AppRoutes.settingsServices,
    staffId: AppRoutes.settingsStaff,
    shiftsId: AppRoutes.shiftsCalendar,
    settingsId: AppRoutes.settings,
  };

  static final List<ShellNavGroup> _groups = [
    ShellNavGroup(
      id: 'main',
      items: [
        ShellNavItem(
          id: homeId,
          label: 'Home',
          icon: LucideIcons.house,
          route: AppRoutes.home,
          isVisible: _hasBranchAssignment,
        ),
        ShellNavItem(
          id: dashboardId,
          label: 'Dashboard',
          icon: LucideIcons.layoutGrid,
          route: AppRoutes.home,
          isVisible: _hasBranchAssignment,
        ),
      ],
    ),
    ShellNavGroup(
      id: 'clinical',
      label: 'Clinical',
      items: [
        ShellNavItem(
          id: patientsId,
          label: 'Patients',
          icon: LucideIcons.users,
          route: AppRoutes.patients,
          isVisible: (p) => p.canViewPatients(),
        ),
        ShellNavItem(
          id: appointmentsId,
          label: 'Appointments',
          icon: LucideIcons.calendar,
          route: AppRoutes.appointments,
          isVisible: (p) => p.canAccessAppointments(),
        ),
        ShellNavItem(
          id: queueNavItemId,
          label: 'Queue',
          icon: LucideIcons.listOrdered,
          route: AppRoutes.appointmentsQueue,
          isVisible: (p) => p.canAccessAppointments(),
          countProvider: appointmentQueueCheckedInCountProvider,
          badgeColor: AppBadgeColor.teal,
        ),
      ],
    ),
    ShellNavGroup(
      id: 'operations',
      label: 'Operations',
      items: [
        ShellNavItem(
          id: billingId,
          label: 'Billing',
          icon: LucideIcons.receipt,
          route: AppRoutes.settingsBilling,
          isVisible: (p) => p.canManageBillingSettings() || p.canViewInvoices(),
        ),
        ShellNavItem(
          id: invoicesId,
          label: 'Invoices',
          icon: LucideIcons.fileText,
          route: AppRoutes.billingInvoices,
          isVisible: (p) => p.canViewInvoices(),
        ),
        ShellNavItem(
          id: servicesId,
          label: 'Services',
          icon: LucideIcons.layoutGrid,
          route: AppRoutes.settingsServices,
          isVisible: (p) => p.canViewServices(),
        ),
        ShellNavItem(
          id: staffId,
          label: 'Staff',
          icon: LucideIcons.userRound,
          route: AppRoutes.settingsStaff,
          isVisible: (p) => p.canManageStaff(),
        ),
        ShellNavItem(
          id: shiftsId,
          label: 'Shifts',
          icon: LucideIcons.calendarDays,
          route: AppRoutes.shiftsCalendar,
          isVisible: (p) => p.canViewShifts(),
        ),
      ],
    ),
  ];

  static final List<ShellNavItem> _footerItems = [
    ShellNavItem(
      id: settingsId,
      label: 'Settings',
      icon: LucideIcons.settings,
      route: AppRoutes.settings,
      isVisible: _hasBranchAssignment,
    ),
  ];

  /// All nav groups with items filtered by [permissionServiceProvider].
  static List<ShellNavGroup> visibleGroups(WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final groups = <ShellNavGroup>[];
    for (final group in _groups) {
      final items = [
        for (final item in group.items)
          if (item.isVisible(permissions)) item,
      ];
      if (items.isNotEmpty) {
        groups.add(ShellNavGroup(id: group.id, label: group.label, items: items));
      }
    }
    return groups;
  }

  /// Footer nav items filtered by permissions (settings + debug dev entries).
  static List<ShellNavItem> visibleFooterItems(WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final items = <ShellNavItem>[
      for (final item in _footerItems)
        if (item.isVisible(permissions)) item,
    ];

    if (kDebugMode) {
      for (final itemId in ShellDevNav.footerItemIds) {
        final label = ShellDevNav.labelFor(itemId);
        final route = ShellDevNav.routeFor(itemId);
        if (label == null || route == null) {
          continue;
        }
        items.add(
          ShellNavItem(
            id: itemId,
            label: label,
            icon: LucideIcons.flaskConical,
            route: route,
            isVisible: _hasBranchAssignment,
          ),
        );
      }
    }

    return items;
  }

  /// Flat list of every visible nav item (groups + footer).
  static List<ShellNavItem> allVisibleItems(WidgetRef ref) {
    return [
      for (final group in visibleGroups(ref)) ...group.items,
      ...visibleFooterItems(ref),
    ];
  }

  /// Returns the route path for [itemId], or null when not wired.
  static String? routeFor(String itemId) => _routesByItemId[itemId] ?? ShellDevNav.routeFor(itemId);

  /// Whether [location] is a generic settings sub-route that should not highlight
  /// primary nav items (org, branches, permissions, etc.).
  static bool isSettingsLocation(String location) {
    if (location == AppRoutes.settings) {
      return false;
    }
    if (location.startsWith('${AppRoutes.settings}/')) {
      if (location.startsWith(AppRoutes.settingsStaff)) {
        return false;
      }
      if (location.startsWith('/settings/services')) {
        return false;
      }
      if (location == AppRoutes.settingsBilling) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// Resolves the nav item id for [location], including parameterized routes.
  static String? itemIdForLocation(String location) {
    if (isSettingsLocation(location)) {
      return null;
    }

    for (final entry in _routesByItemId.entries) {
      if (entry.value == location) {
        return entry.key;
      }
    }

    if (location == AppRoutes.patients || location.startsWith('${AppRoutes.patients}/')) {
      return patientsId;
    }

    if (location == AppRoutes.appointmentsQueue) {
      return queueNavItemId;
    }

    if (location.startsWith(AppRoutes.appointments)) {
      return appointmentsId;
    }

    if (location.startsWith(AppRoutes.billingInvoices)) {
      return invoicesId;
    }

    if (location == AppRoutes.billingInsuranceProviders || location == AppRoutes.settingsBilling) {
      return billingId;
    }

    if (location.startsWith('/settings/services')) {
      return servicesId;
    }

    if (location.startsWith(AppRoutes.settingsStaff)) {
      return staffId;
    }

    if (location.startsWith(AppRoutes.shifts)) {
      return shiftsId;
    }

    return ShellDevNav.itemIdForLocation(location);
  }

  /// Label for [itemId], or null if unknown.
  static String? labelFor(String itemId) {
    final devLabel = ShellDevNav.labelFor(itemId);
    if (devLabel != null) {
      return devLabel;
    }

    for (final item in [..._groups.expand((g) => g.items), ..._footerItems]) {
      if (item.id == itemId) {
        return item.label;
      }
    }
    return null;
  }

  /// Default selected item when no location matches.
  static String defaultItemId() => homeId;

  static bool _hasBranchAssignment(PermissionService permissions) {
    return permissions.canViewShifts();
  }
}

/// One navigable destination in the shell sidebar.
@immutable
class ShellNavItem {
  const ShellNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    required this.isVisible,
    this.countProvider,
    this.badgeColor = AppBadgeColor.neutral,
  });

  final String id;
  final String label;
  final IconData icon;
  final String route;
  final ShellNavPermissionPredicate isVisible;
  final Provider<int>? countProvider;
  final AppBadgeColor badgeColor;
}

/// Labeled group of [ShellNavItem] entries in the sidebar.
@immutable
class ShellNavGroup {
  const ShellNavGroup({
    required this.id,
    required this.items,
    this.label,
  });

  final String id;
  final String? label;
  final List<ShellNavItem> items;
}
