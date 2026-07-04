import 'package:flutter/material.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_model.dart';

/// Clinic navigation tree and route bindings for [AppSidebar].
abstract final class ShellNavConfig {
  static const Map<String, String> _routesByItemId = {
    'home': AppRoutes.home,
    'dashboard': AppRoutes.home,
    'patients': AppRoutes.patients,
    'appointments': AppRoutes.appointments,
    'billing': AppRoutes.billingInvoices,
    'invoices': AppRoutes.billingInvoices,
    'services': AppRoutes.settingsServices,
    'staff': AppRoutes.settingsStaff,
    'shifts': AppRoutes.shiftsCalendar,
    'settings': AppRoutes.settings,
    'dev': AppRoutes.foundationDemo,
  };

  static const List<ShellNavGroup> groups = [
    ShellNavGroup(
      id: 'main',
      items: [
        ShellNavItem(id: 'home', label: 'Home', icon: Icons.home_outlined),
        ShellNavItem(id: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
      ],
    ),
    ShellNavGroup(
      id: 'clinical',
      label: 'Clinical',
      items: [
        ShellNavItem(id: 'patients', label: 'Patients', icon: Icons.people_outline),
        ShellNavItem(id: 'appointments', label: 'Appointments', icon: Icons.calendar_month_outlined),
        ShellNavItem(id: 'encounters', label: 'Encounters', icon: Icons.medical_services_outlined),
        ShellNavItem(id: 'workspace', label: 'Workspace', icon: Icons.assignment_outlined),
      ],
    ),
    ShellNavGroup(
      id: 'operations',
      label: 'Operations',
      items: [
        ShellNavItem(id: 'billing', label: 'Billing', icon: Icons.receipt_long_outlined),
        ShellNavItem(id: 'invoices', label: 'Invoices', icon: Icons.description_outlined),
        ShellNavItem(id: 'services', label: 'Services', icon: Icons.grid_view_outlined),
        ShellNavItem(id: 'staff', label: 'Staff', icon: Icons.person_outline),
        ShellNavItem(id: 'shifts', label: 'Shifts', icon: Icons.event_outlined),
        ShellNavItem(id: 'reports', label: 'Reports', icon: Icons.bar_chart_outlined),
      ],
    ),
  ];

  static List<ShellNavItem> footerItems() {
    final items = <ShellNavItem>[const ShellNavItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined)];

    if (ShellDevNav.isEnabled) {
      items.add(const ShellNavItem(id: 'dev', label: 'Dev', icon: Icons.science_outlined));
    }

    return items;
  }

  static List<ShellNavItem> get allItems => [for (final group in groups) ...group.items, ...footerItems()];

  static String? routeFor(String itemId) => _routesByItemId[itemId] ?? ShellDevNav.routeFor(itemId);

  static bool isSettingsLocation(String location) {
    return location == AppRoutes.settings || location.startsWith('${AppRoutes.settings}/');
  }

  static bool isDesignSystemLocation(String location) {
    return location == AppRoutes.foundationDemo;
  }

  static String? pageTitleForLocation(String location) {
    if (isSettingsLocation(location)) {
      return 'Settings';
    }
    if (isDesignSystemLocation(location)) {
      return 'Design System';
    }

    final itemId = itemIdForLocation(location);
    return itemId != null ? labelFor(itemId) : null;
  }

  static String? itemIdForLocation(String location) {
    for (final entry in _routesByItemId.entries) {
      if (entry.value == location) {
        return entry.key;
      }
    }

    if (location == AppRoutes.home) {
      return 'home';
    }
    if (location == AppRoutes.patients || location.startsWith('${AppRoutes.patients}/')) {
      return 'patients';
    }
    if (location.startsWith(AppRoutes.appointments)) {
      return 'appointments';
    }
    if (location.startsWith(AppRoutes.billingInvoices)) {
      return 'invoices';
    }
    if (location.startsWith(AppRoutes.settingsServices)) {
      return 'services';
    }
    if (location.startsWith(AppRoutes.settingsStaff)) {
      return 'staff';
    }
    if (location.startsWith(AppRoutes.shifts)) {
      return 'shifts';
    }
    if (location == AppRoutes.foundationDemo) {
      return 'dev';
    }

    return ShellDevNav.itemIdForLocation(location);
  }

  static String? labelFor(String itemId) {
    final devLabel = ShellDevNav.labelFor(itemId);
    if (devLabel != null) {
      return devLabel;
    }

    for (final item in allItems) {
      if (item.id == itemId) {
        return item.label;
      }
    }
    return null;
  }
}
