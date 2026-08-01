import 'package:flutter/material.dart';

/// Definition for a personal settings screen shown in [SettingsRail].
@immutable
class SettingsScreenDefinition {
  const SettingsScreenDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
}

/// Static catalog of personal settings screens (web `SETTINGS_SCREENS`).
abstract final class SettingsScreens {
  static const appearance = SettingsScreenDefinition(
    id: 'appearance',
    label: 'Appearance',
    description: 'Theme, language, and display formats',
    icon: Icons.palette_outlined,
  );

  static const notifications = SettingsScreenDefinition(
    id: 'notifications',
    label: 'Notifications',
    description: 'Alerts and delivery preferences',
    icon: Icons.notifications_outlined,
  );

  static const security = SettingsScreenDefinition(
    id: 'security',
    label: 'Security',
    description: 'Workstation idle sign-out',
    icon: Icons.shield_outlined,
  );

  static const all = <SettingsScreenDefinition>[appearance, notifications, security];

  static const defaultId = 'appearance';

  static SettingsScreenDefinition? byId(String? id) {
    if (id == null) {
      return null;
    }
    for (final screen in all) {
      if (screen.id == id) {
        return screen;
      }
    }
    return null;
  }

  static SettingsScreenDefinition resolve(String? id) => byId(id) ?? appearance;

  static String routeFor(String id) => '/settings/$id';
}
