import 'package:flutter/material.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';

/// Static clinic navigation tree and route bindings for the authenticated shell.
abstract final class ShellNavConfig {
  static const themeShowcaseId = 'theme-showcase';

  static const Map<String, String> _routesByItemId = {
    'dashboard': AppRoutes.home,
    'patients-list': AppRoutes.patients,
    'patients-register': AppRoutes.patientsNew,
    'appointments-calendar': AppRoutes.appointmentsCalendar,
    'appointments-book': AppRoutes.appointmentsBook,
    'appointments-queue': AppRoutes.appointmentsQueue,
    'billing-invoices': AppRoutes.billingInvoices,
    'billing-insurance': AppRoutes.billingInsuranceProviders,
    'shifts': AppRoutes.shiftsCalendar,
    'settings-organization': AppRoutes.settingsOrganization,
    'settings-branches': AppRoutes.settingsBranches,
    'settings-staff': AppRoutes.settingsStaff,
    'settings-permissions': AppRoutes.settingsPermissions,
    themeShowcaseId: AppRoutes.foundationDemo,
  };

  static const ShellNavSingle themeShowcaseFooter = ShellNavSingle(
    id: themeShowcaseId,
    label: 'Theme showcase',
    icon: Icons.palette_outlined,
  );

  static const List<ShellNavEntry> entries = [
    ShellNavSingle(id: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
    ShellNavSingle(id: 'reception', label: 'Reception desk', icon: Icons.desk_outlined),
    ShellNavGroup(
      id: 'patients',
      label: 'Patients',
      icon: Icons.people_outline,
      children: [
        ShellNavSingle(id: 'patients-list', label: 'Patient list', icon: Icons.list_alt_outlined),
        ShellNavSingle(
          id: 'patients-register',
          label: 'Register patient',
          icon: Icons.person_add_outlined,
          badgeCount: 3,
          badgeTone: ShellNavBadgeTone.warning,
        ),
      ],
    ),
    ShellNavGroup(
      id: 'appointments',
      label: 'Appointments',
      icon: Icons.calendar_month_outlined,
      children: [
        ShellNavSingle(id: 'appointments-calendar', label: 'Calendar', icon: Icons.calendar_view_month_outlined),
        ShellNavSingle(id: 'appointments-book', label: 'Book appointment', icon: Icons.event_available_outlined),
        ShellNavSingle(
          id: 'appointments-queue',
          label: 'Queue',
          icon: Icons.queue_outlined,
          badgeCount: 8,
          badgeTone: ShellNavBadgeTone.success,
        ),
      ],
    ),
    ShellNavGroup(
      id: 'billing',
      label: 'Billing',
      icon: Icons.receipt_long_outlined,
      children: [
        ShellNavSingle(id: 'billing-invoices', label: 'Invoices', icon: Icons.description_outlined),
        ShellNavSingle(id: 'billing-insurance', label: 'Insurance', icon: Icons.health_and_safety_outlined),
      ],
    ),
    ShellNavSingle(id: 'shifts', label: 'Shifts', icon: Icons.schedule_outlined),
    ShellNavGroup(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      children: [
        ShellNavSingle(id: 'settings-organization', label: 'Organization', icon: Icons.business_outlined),
        ShellNavSingle(id: 'settings-branches', label: 'Branches', icon: Icons.store_outlined),
        ShellNavSingle(
          id: 'settings-staff',
          label: 'Staff',
          icon: Icons.badge_outlined,
          badgeCount: 2,
          badgeTone: ShellNavBadgeTone.neutral,
        ),
        ShellNavSingle(id: 'settings-permissions', label: 'Permissions', icon: Icons.admin_panel_settings_outlined),
      ],
    ),
  ];

  /// Returns the route path for [itemId], or null when the item is not wired yet.
  static String? routeFor(String itemId) => _routesByItemId[itemId];

  /// Resolves the nav item id for [location], including parameterized feature routes.
  static String? itemIdForLocation(String location) {
    for (final entry in _routesByItemId.entries) {
      if (entry.value == location) {
        return entry.key;
      }
    }

    if (location == AppRoutes.patientsNew) {
      return 'patients-register';
    }
    if (location == AppRoutes.patients || location.startsWith('${AppRoutes.patients}/')) {
      return 'patients-list';
    }

    if (location == AppRoutes.appointmentsCalendar) {
      return 'appointments-calendar';
    }
    if (location == AppRoutes.appointmentsBook) {
      return 'appointments-book';
    }
    if (location == AppRoutes.appointmentsQueue) {
      return 'appointments-queue';
    }

    if (location == AppRoutes.billingInsuranceProviders ||
        location.startsWith('${AppRoutes.billingInsuranceProviders}/')) {
      return 'billing-insurance';
    }
    if (location == AppRoutes.billingInvoices || location.startsWith('${AppRoutes.billingInvoices}/')) {
      return 'billing-invoices';
    }

    if (location == AppRoutes.shiftsNew || location.startsWith('${AppRoutes.shifts}/')) {
      return 'shifts';
    }

    if (location == AppRoutes.settingsBranchesNew || location.startsWith('${AppRoutes.settingsBranches}/')) {
      return 'settings-branches';
    }
    if (location == AppRoutes.settingsStaffNew || location.startsWith('${AppRoutes.settingsStaff}/')) {
      return 'settings-staff';
    }

    return null;
  }

  /// Returns the label for [itemId], or null if not found.
  static String? labelFor(String itemId) {
    if (itemId == themeShowcaseFooter.id) {
      return themeShowcaseFooter.label;
    }

    for (final entry in entries) {
      switch (entry) {
        case ShellNavSingle(:final id, :final label):
          if (id == itemId) return label;
        case ShellNavGroup(:final children):
          for (final child in children) {
            if (child.id == itemId) return child.label;
          }
      }
    }
    return null;
  }

  /// Returns the group id containing [itemId], or null if top-level / not found.
  static String? groupIdFor(String itemId) {
    for (final entry in entries) {
      if (entry case ShellNavGroup(:final id, :final children)) {
        for (final child in children) {
          if (child.id == itemId) return id;
        }
      }
    }
    return null;
  }

  /// Default selected item: first child of the first group, else first single item.
  static String defaultSelectedId() {
    for (final entry in entries) {
      if (entry case ShellNavGroup(:final children) when children.isNotEmpty) {
        return children.first.id;
      }
    }
    for (final entry in entries) {
      if (entry case ShellNavSingle(:final id)) {
        return id;
      }
    }
    return 'dashboard';
  }

  /// Group ids that should start expanded (contains default selection).
  static Set<String> defaultExpandedGroupIds() {
    final selectedId = defaultSelectedId();
    final groupId = groupIdFor(selectedId);
    return groupId == null ? <String>{} : {groupId};
  }
}
