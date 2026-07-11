// Web parity: settings.ts exports use SCREAMING_SNAKE_CASE constant names.
// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

typedef SettingsScreenId = String;

/// Metadata for a settings page tab (web `SettingsScreenMeta`).
@immutable
class SettingsScreenMeta {
  const SettingsScreenMeta({required this.id, required this.label, required this.description});

  final SettingsScreenId id;
  final String label;
  final String description;
}

const List<SettingsScreenMeta> settingsScreens = [
  SettingsScreenMeta(id: 'general', label: 'General', description: 'Organization profile and regional defaults'),
  SettingsScreenMeta(id: 'branches', label: 'Branches', description: 'Locations, hours, and contact details'),
  SettingsScreenMeta(id: 'staff', label: 'Staff', description: 'Team members, roles, and access'),
  SettingsScreenMeta(id: 'services', label: 'Services', description: 'Procedures and billable catalog'),
  SettingsScreenMeta(id: 'notifications', label: 'Notifications', description: 'Alerts and delivery preferences'),
];

const List<SettingsScreenMeta> SETTINGS_SCREENS = settingsScreens;

/// Lucide → Material icon mapping from web `SETTINGS_NAV_ICONS`.
const Map<SettingsScreenId, IconData> settingsNavIcons = {
  'general': Icons.business,
  'branches': Icons.location_on,
  'staff': Icons.group,
  'services': Icons.medical_services,
  'notifications': Icons.notifications,
};

const Map<SettingsScreenId, IconData> SETTINGS_NAV_ICONS = settingsNavIcons;