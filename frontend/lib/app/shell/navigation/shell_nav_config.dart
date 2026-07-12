import 'package:flutter/material.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';
import 'package:ai_clinic/features/design_system/presentation/dev_section.dart';

/// Clinic navigation tree and route bindings for [AppSidebar].
abstract final class ShellNavConfig {
  static const List<AppNavGroup> groups = kClinicNavGroups;

  static const Map<String, String> _routesByItemId = {
    'home': AppRoutes.home,
    'dashboard': AppRoutes.dashboard,
    'patients': AppRoutes.patients,
    'appointments': AppRoutes.appointments,
    'appointments-calendar': AppRoutes.appointmentsCalendar,
    'encounters': AppRoutes.encounters,
    'workspace': AppRoutes.workspace,
    'billing': AppRoutes.billing,
    'invoices': AppRoutes.billingInvoices,
    'services': AppRoutes.settingsServices,
    'clinic-management': AppRoutes.clinicManagement,
    'staff': AppRoutes.clinicManagement,
    'shifts': AppRoutes.shiftsCalendar,
    'reports': AppRoutes.reports,
    'settings': AppRoutes.settings,
    'dev': AppRoutes.foundationDemo,
  };

  static List<AppNavItem> footerItems() {
    return [
      for (final item in kClinicNavFooter)
        if (item.id != 'dev' || ShellDevNav.isEnabled) item,
      ...devActionItems(),
    ];
  }

  /// Debug-only dev tooling entries in the sidebar footer (siblings of Settings/Dev).
  static List<AppNavItem> devActionItems() {
    if (!ShellDevNav.isEnabled) {
      return const [];
    }

    return [
      for (final itemId in ShellDevNav.actionItemIds)
        AppNavItem(
          id: itemId,
          label: ShellDevNav.labelFor(itemId) ?? itemId,
          icon: ShellDevNav.iconFor(itemId) ?? Icons.build_outlined,
        ),
    ];
  }

  static List<AppNavItem> get allItems => [for (final group in groups) ...group.items, ...footerItems()];

  static String? routeFor(String itemId) => _routesByItemId[itemId] ?? ShellDevNav.routeFor(itemId);

  /// Shell routes reachable without signing in during debug scaffold preview.
  ///
  /// Open-access design-system routes are included so the router allows navigation,
  /// but [shouldUseUnauthenticatedPreviewPlaceholder] keeps them on live builders.
  static bool allowsUnauthenticatedPreview(String location) {
    if (ShellDevNav.allowsOpenAccess(location)) {
      return true;
    }

    final itemId = itemIdForLocation(location);
    return itemId != null && itemId != 'dev';
  }

  /// When true, shell child routes must render static placeholders instead of
  /// authenticated feature pages (see auth review §2.2).
  static bool shouldUseUnauthenticatedPreviewPlaceholder(String location) {
    return allowsUnauthenticatedPreview(location) && !ShellDevNav.allowsOpenAccess(location);
  }

  static bool isSettingsLocation(String location) {
    return location == AppRoutes.settings || location.startsWith('${AppRoutes.settings}/');
  }

  static bool isDesignSystemLocation(String location) {
    return location == AppRoutes.foundationDemo;
  }

  static bool isFullWidthLocation(String location) {
    return location == AppRoutes.patients ||
        location.startsWith('${AppRoutes.patients}/') ||
        location == AppRoutes.clinicManagement ||
        location == AppRoutes.appointmentsCalendar;
  }

  /// Routes whose content should fill the shell viewport (no outer scroll).
  static bool isFillViewportLocation(String location) {
    return location == AppRoutes.appointmentsCalendar;
  }

  static DevSection devSectionForUri(Uri uri) {
    if (!isDesignSystemLocation(uri.path)) {
      return DevSection.foundations;
    }
    return DevSectionId.fromId(uri.queryParameters['section'] ?? 'components');
  }

  static bool isDesignSystemFullWidth(Uri uri) {
    if (!isDesignSystemLocation(uri.path)) {
      return false;
    }
    final section = devSectionForUri(uri);
    return section == DevSection.components || section == DevSection.patterns;
  }

  static String devSectionBreadcrumbLabel(DevSection section) => switch (section) {
    DevSection.foundations => 'Foundations',
    DevSection.patterns => 'Patterns',
    DevSection.guidelines => 'Guidelines',
    DevSection.components => 'Components',
  };

  static String? pageTitleForLocation(String location) {
    if (isDesignSystemLocation(location)) {
      return 'Design System';
    }

    final itemId = itemIdForLocation(location);
    return itemId != null ? labelFor(itemId) : null;
  }

  static AppBreadcrumb? breadcrumbForLocation(String location, {Uri? uri, void Function(String route)? onNavigate}) {
    final itemId = itemIdForLocation(location);
    if (itemId == null) {
      return null;
    }

    if (itemId == 'dev' && uri != null) {
      final section = devSectionForUri(uri);
      return AppBreadcrumb(
        items: [
          AppBreadcrumbItem(
            label: 'Dev',
            onTap: onNavigate == null ? null : () => onNavigate(AppRoutes.foundationDemo),
          ),
          AppBreadcrumbItem(label: devSectionBreadcrumbLabel(section)),
        ],
      );
    }

    final pageLabel = pageTitleForLocation(location) ?? labelFor(itemId);
    if (pageLabel == null) {
      return null;
    }

    return AppBreadcrumb(items: [AppBreadcrumbItem(label: pageLabel)]);
  }

  static String? groupLabelFor(String itemId) {
    for (final group in groups) {
      if (group.items.any((item) => item.id == itemId)) {
        return group.label;
      }
    }
    return null;
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
    if (location == AppRoutes.appointmentsCalendar) {
      return 'appointments-calendar';
    }
    if (location.startsWith(AppRoutes.appointments)) {
      return 'appointments';
    }
    if (location == AppRoutes.billing) {
      return 'billing';
    }
    if (location.startsWith(AppRoutes.billingInvoices)) {
      return 'invoices';
    }
    if (location.startsWith(AppRoutes.settingsServices)) {
      return 'services';
    }
    if (location == AppRoutes.clinicManagement) {
      return 'clinic-management';
    }
    if (AppRoutes.adminSettingsPaths.contains(location) ||
        location.startsWith('${AppRoutes.settingsBranches}/') ||
        (location.startsWith('${AppRoutes.settingsStaff}/') && location != AppRoutes.settingsStaffNew)) {
      return 'clinic-management';
    }
    if (location.startsWith(AppRoutes.shifts)) {
      return 'shifts';
    }
    if (location == AppRoutes.dashboard) {
      return 'dashboard';
    }
    if (location == AppRoutes.encounters) {
      return 'encounters';
    }
    if (location == AppRoutes.workspace) {
      return 'workspace';
    }
    if (location == AppRoutes.reports) {
      return 'reports';
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
