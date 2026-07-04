import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/foundation.dart';

/// Logical grouping for command palette results.
enum AppCommandGroup {
  navigate,
  patients,
  actions,
  search,
  ai;

  String get label => switch (this) {
    AppCommandGroup.navigate => 'Navigate',
    AppCommandGroup.patients => 'Patients',
    AppCommandGroup.actions => 'Actions',
    AppCommandGroup.search => 'Search',
    AppCommandGroup.ai => 'AI',
  };

  /// Stable ordering when rendering grouped sections.
  int get sortOrder => switch (this) {
    AppCommandGroup.navigate => 0,
    AppCommandGroup.patients => 1,
    AppCommandGroup.search => 2,
    AppCommandGroup.actions => 3,
    AppCommandGroup.ai => 4,
  };
}

/// Well-known id for the palette "Ask AI…" affordance.
const appCommandAskAiId = '__ask_ai__';

/// A single selectable row in [AppCommandBar].
class AppCommandItem {
  const AppCommandItem({
    required this.id,
    required this.label,
    required this.group,
    this.meta,
    this.icon,
    this.iconAi = false,
    this.avatarName,
    this.shortcutKeys,
    this.keywords = const [],
    this.route,
    this.onSelected,
    this.isVisible,
  }) : assert(route != null || onSelected != null || id == appCommandAskAiId);

  final String id;
  final String label;
  final AppCommandGroup group;
  final String? meta;
  final IconData? icon;
  final bool iconAi;
  final String? avatarName;
  final List<String>? shortcutKeys;
  final List<String> keywords;
  final String? route;
  final VoidCallback? onSelected;

  /// When non-null, the item is omitted unless this returns `true`.
  final bool Function(PermissionService permissions)? isVisible;

  bool matchesQuery(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    if (label.toLowerCase().contains(query)) {
      return true;
    }
    if (meta != null && meta!.toLowerCase().contains(query)) {
      return true;
    }
    if (group.label.toLowerCase().contains(query)) {
      return true;
    }
    for (final keyword in keywords) {
      if (keyword.toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }
}

/// Platform-aware modifier label for shortcut chips.
String appCommandModifierKeyLabel() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => '⌘',
    _ => 'Ctrl',
  };
}

/// Default static command items: navigation targets and common actions.
///
/// Patient search rows are injected at runtime by [AppCommandBar].
List<AppCommandItem> buildDefaultCommandItems({
  required void Function(String route) navigate,
  required PermissionService permissions,
}) {
  final mod = appCommandModifierKeyLabel();

  AppCommandItem nav({
    required String id,
    required String label,
    required String route,
    List<String> keywords = const [],
    bool Function(PermissionService permissions)? visible,
  }) {
    return AppCommandItem(
      id: id,
      label: label,
      group: AppCommandGroup.navigate,
      route: route,
      keywords: keywords,
      isVisible: visible,
      onSelected: () => navigate(route),
    );
  }

  AppCommandItem action({
    required String id,
    required String label,
    required String route,
    required IconData icon,
    List<String>? shortcutKeys,
    bool Function(PermissionService permissions)? visible,
    List<String> keywords = const [],
  }) {
    return AppCommandItem(
      id: id,
      label: label,
      group: AppCommandGroup.actions,
      icon: icon,
      route: route,
      shortcutKeys: shortcutKeys,
      keywords: keywords,
      isVisible: visible,
      onSelected: () => navigate(route),
    );
  }

  return [
    nav(id: 'home', label: 'Home', route: AppRoutes.home, keywords: const ['dashboard']),
    nav(
      id: 'patients',
      label: 'Patients',
      route: AppRoutes.patients,
      visible: (p) => p.canViewPatients(),
    ),
    nav(
      id: 'appointments',
      label: 'Appointments',
      route: AppRoutes.appointments,
      visible: (p) => p.canAccessAppointments(),
    ),
    nav(
      id: 'billing',
      label: 'Billing',
      route: AppRoutes.billingInvoices,
      keywords: const ['invoices'],
      visible: (p) => p.canViewInvoices(),
    ),
    nav(
      id: 'shifts',
      label: 'Shifts',
      route: AppRoutes.shiftsCalendar,
      visible: (p) => p.canViewShifts(),
    ),
    nav(
      id: 'settings',
      label: 'Settings',
      route: AppRoutes.settings,
      keywords: const ['preferences', 'admin'],
    ),
    action(
      id: 'new-patient',
      label: 'New patient',
      route: AppRoutes.patientsNew,
      icon: LucideIcons.userPlus,
      shortcutKeys: [mod, 'N'],
      visible: (p) => p.canCreatePatients(),
      keywords: const ['register', 'create'],
    ),
    action(
      id: 'new-invoice',
      label: 'New invoice',
      route: AppRoutes.billingInvoices,
      icon: LucideIcons.fileText,
      shortcutKeys: [mod, 'I'],
      visible: (p) => p.canCreateInvoices(),
      keywords: const ['billing', 'create'],
    ),
    action(
      id: 'new-appointment',
      label: 'New appointment',
      route: AppRoutes.appointmentsBook,
      icon: LucideIcons.plus,
      visible: (p) => p.canCreateAppointments(),
      keywords: const ['book', 'schedule'],
    ),
  ];
}
