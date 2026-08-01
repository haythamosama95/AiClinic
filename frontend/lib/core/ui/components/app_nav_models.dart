import 'package:flutter/material.dart';

/// A single navigation entry in [AppNavGroup] or footer lists.
@immutable
class AppNavItem {
  const AppNavItem({required this.id, required this.label, required this.icon, this.count});

  final String id;
  final String label;
  final IconData icon;
  final int? count;
}

/// A labelled group of [AppNavItem] entries in the sidebar.
@immutable
class AppNavGroup {
  const AppNavGroup({required this.id, this.label, required this.items});

  final String id;
  final String? label;
  final List<AppNavItem> items;
}

/// Clinic branch metadata for branch switcher and shell chrome.
@immutable
class AppBranch {
  const AppBranch({required this.id, required this.name, required this.org});

  final String id;
  final String name;
  final String org;
}

/// Signed-in user metadata for the user menu.
@immutable
class AppUserMenuUser {
  const AppUserMenuUser({required this.name, required this.role, required this.email});

  final String name;
  final String role;
  final String email;
}

const kMockOrg = 'AiClinic Health Group';

const kMockBranches = <AppBranch>[
  AppBranch(id: 'downtown', name: 'Downtown Clinic', org: kMockOrg),
  AppBranch(id: 'nasr-city', name: 'Nasr City', org: kMockOrg),
  AppBranch(id: 'alexandria', name: 'Alexandria', org: kMockOrg),
];

const kMockUser = AppUserMenuUser(name: 'Dr. Sarah Ali', role: 'Physician', email: 'sarah.ali@aiclinic.health');

int kMockNotificationCount([int count = 3]) => count;

const kClinicNavGroups = <AppNavGroup>[
  AppNavGroup(
    id: 'main',
    items: [
      AppNavItem(id: 'home', label: 'Home', icon: Icons.home_outlined),
      AppNavItem(id: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
    ],
  ),
  AppNavGroup(
    id: 'clinical',
    label: 'Clinical',
    items: [
      AppNavItem(id: 'patients', label: 'Patients', icon: Icons.people_outline),
      AppNavItem(id: 'appointments', label: 'Appointments', icon: Icons.calendar_month_outlined),
<<<<<<< HEAD
=======
      AppNavItem(id: 'appointments-queue', label: 'Queue', icon: Icons.queue_outlined),
>>>>>>> master
      AppNavItem(id: 'appointments-calendar', label: 'Calendar', icon: Icons.event_outlined),
      AppNavItem(id: 'encounters', label: 'Encounters', icon: Icons.medical_services_outlined),
      AppNavItem(id: 'workspace', label: 'Workspace', icon: Icons.assignment_outlined),
    ],
  ),
  AppNavGroup(
    id: 'operations',
    label: 'Operations',
    items: [
      AppNavItem(id: 'invoices', label: 'Invoices', icon: Icons.description_outlined),
      AppNavItem(id: 'services', label: 'Services', icon: Icons.grid_view_outlined),
      AppNavItem(id: 'clinic-management', label: 'Clinic Management', icon: Icons.apartment_outlined),
      AppNavItem(id: 'shifts', label: 'Shifts', icon: Icons.event_outlined),
      AppNavItem(id: 'reports', label: 'Reports', icon: Icons.bar_chart_outlined),
    ],
  ),
];

const _showcaseNavCounts = <String, int>{'patients': 128, 'appointments': 12, 'invoices': 5};

/// Showcase-only copy of [kClinicNavGroups] with demo badge counts.
List<AppNavGroup> clinicNavGroupsForShowcase() => [
  for (final group in kClinicNavGroups)
    AppNavGroup(
      id: group.id,
      label: group.label,
      items: [
        for (final item in group.items)
          AppNavItem(id: item.id, label: item.label, icon: item.icon, count: _showcaseNavCounts[item.id]),
      ],
    ),
];

const kClinicNavFooter = <AppNavItem>[
  AppNavItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined),
  AppNavItem(id: 'dev', label: 'Dev', icon: Icons.science_outlined),
];

final kAllNavItems = <AppNavItem>[for (final group in kClinicNavGroups) ...group.items, ...kClinicNavFooter];
