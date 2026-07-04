import 'package:flutter/foundation.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_fill_dummy_clinic.dart';

/// Debug-only shell nav metadata for dev tooling routes.
abstract final class ShellDevNav {
  const ShellDevNav._();

  static const groupId = 'dev-options';
  static const themeShowcaseId = 'theme-showcase';
  static const resetDatabaseId = 'reset-database';

  static const Map<String, String> _routesByItemId = {themeShowcaseId: AppRoutes.foundationDemo};

  static bool get isEnabled => kDebugMode;

  static List<String> get footerItemIds => [
    themeShowcaseId,
    if (ShellDevFillDummyClinic.isEnabled) ShellDevFillDummyClinic.itemId,
    resetDatabaseId,
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
    resetDatabaseId => 'Reset Database',
    _ => null,
  };

  static String? groupIdFor(String itemId) => footerItemIds.contains(itemId) ? groupId : null;
}
