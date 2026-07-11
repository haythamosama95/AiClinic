import 'package:flutter/material.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';

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

  static const all = <SettingsTabDefinition>[general];

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
  static List<SettingsTabDefinition> visibleFor(AuthSessionState auth) => [general];
}
