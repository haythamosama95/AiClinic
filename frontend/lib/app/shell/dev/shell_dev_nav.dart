import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_reset_clinic.dart';

/// Debug-only shell nav metadata for dev tooling routes.
abstract final class ShellDevNav {
  const ShellDevNav._();

  static const groupId = 'dev-options';
  static const themeShowcaseId = 'theme-showcase';

  static const Map<String, String> _routesByItemId = {themeShowcaseId: AppRoutes.foundationDemo};

  static bool get isEnabled => kDebugMode;

  static bool isDesignSystemRoute(String location) => location == AppRoutes.foundationDemo;

  /// Debug-only: design system page is reachable without login and startup view locks.
  static bool allowsOpenAccess(String location) => kDebugMode && isDesignSystemRoute(location);

  static List<String> get footerItemIds => [themeShowcaseId, ...actionItemIds];

  static List<String> get actionItemIds => [
    if (ShellDevFillDummyClinic.isEnabled) ShellDevFillDummyClinic.itemId,
    if (ShellDevResetClinic.isEnabled) ShellDevResetClinic.itemId,
  ];

  static String? routeFor(String itemId) => _routesByItemId[itemId];

  static String? itemIdForLocation(String location) {
    for (final entry in _routesByItemId.entries) {
      if (entry.value == location) {
        return entry.key;
      }
    }
    return null;
  }

  static String? labelFor(String itemId) => switch (itemId) {
    themeShowcaseId => 'Theme Showcase',
    ShellDevFillDummyClinic.itemId => ShellDevFillDummyClinic.label,
    ShellDevResetClinic.itemId => ShellDevResetClinic.label,
    _ => null,
  };

  static IconData? iconFor(String itemId) => switch (itemId) {
    themeShowcaseId => Icons.palette_outlined,
    ShellDevFillDummyClinic.itemId => ShellDevFillDummyClinic.icon,
    ShellDevResetClinic.itemId => ShellDevResetClinic.icon,
    _ => null,
  };

  static String? groupIdFor(String itemId) => footerItemIds.contains(itemId) ? groupId : null;
}
