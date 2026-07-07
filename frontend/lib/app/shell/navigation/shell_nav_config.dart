import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_nav.dart';
import 'package:ai_clinic/core/ui/components/app_breadcrumb.dart';
import 'package:ai_clinic/core/ui/components/app_nav_models.dart';

/// Clinic navigation tree and route bindings for [AppSidebar].
abstract final class ShellNavConfig {
  static const List<AppNavGroup> groups = kClinicNavGroups;

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

  static List<AppNavItem> footerItems() {
    return [
      for (final item in kClinicNavFooter)
        if (item.id != 'dev' || ShellDevNav.isEnabled) item,
    ];
  }

  static List<AppNavItem> get allItems => [for (final group in groups) ...group.items, ...footerItems()];

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

  static AppBreadcrumb? breadcrumbForLocation(String location) {
    final itemId = itemIdForLocation(location);
    if (itemId == null) {
      return null;
    }

    final pageLabel = pageTitleForLocation(location) ?? labelFor(itemId);
    if (pageLabel == null) {
      return null;
    }

    final groupLabel = groupLabelFor(itemId);
    if (groupLabel != null && groupLabel != pageLabel) {
      return AppBreadcrumb(
        items: [
          AppBreadcrumbItem(label: groupLabel),
          AppBreadcrumbItem(label: pageLabel),
        ],
      );
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
