import 'package:flutter/material.dart';

/// Definition for a settings section tab shown in [SettingsTabBar].
@immutable
class SettingsTabDefinition {
  const SettingsTabDefinition({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final IconData icon;
}

/// Static catalog of settings tabs (order matches the settings header design).
abstract final class SettingsTabs {
  static const general = SettingsTabDefinition(id: 'general', label: 'General', icon: Icons.tune_outlined);

  static const staff = SettingsTabDefinition(id: 'staff', label: 'Staff Management', icon: Icons.people_outlined);

  static const staffRoles = SettingsTabDefinition(id: 'staff-roles', label: 'Staff Roles', icon: Icons.badge_outlined);

  static const all = <SettingsTabDefinition>[general, staff, staffRoles];

  static const defaultTabId = 'general';

  static SettingsTabDefinition? byId(String id) {
    for (final tab in all) {
      if (tab.id == id) {
        return tab;
      }
    }
    return null;
  }

  /// Tabs visible for the current session.
  static List<SettingsTabDefinition> visibleFor() {
    return all;
  }
}
