import 'package:flutter/material.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';

/// Static clinic navigation tree and route bindings for the authenticated shell.
abstract final class ShellNavConfig {
  static const themeShowcaseId = 'theme-showcase';

  static const Map<String, String> _routesByItemId = {
    'dashboard': AppRoutes.home,
    'appointments-calendar': AppRoutes.appointmentsCalendar,
    'appointments-book': AppRoutes.appointmentsBook,
    'appointments-queue': AppRoutes.appointmentsQueue,
    themeShowcaseId: AppRoutes.foundationDemo,
  };

  static const ShellNavSingle themeShowcaseFooter = ShellNavSingle(
    id: themeShowcaseId,
    label: 'Theme showcase',
    icon: Icons.palette_outlined,
  );

  static const List<ShellNavEntry> entries = [
    ShellNavSingle(id: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
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

    if (location == AppRoutes.appointmentsCalendar) {
      return 'appointments-calendar';
    }
    if (location == AppRoutes.appointmentsBook) {
      return 'appointments-book';
    }
    if (location == AppRoutes.appointmentsQueue) {
      return 'appointments-queue';
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

  /// Default selected item: first entry in [entries] (single id or first group child).
  static String defaultSelectedId() {
    for (final entry in entries) {
      switch (entry) {
        case ShellNavSingle(:final id):
          return id;
        case ShellNavGroup(:final children) when children.isNotEmpty:
          return children.first.id;
        case ShellNavGroup():
          continue;
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
