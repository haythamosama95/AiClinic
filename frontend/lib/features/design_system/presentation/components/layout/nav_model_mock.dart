import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_nav_models.dart';

/// Showcase-only org label (web `MOCK_ORG`).
const mockOrg = 'AiClinic Health Group';

/// Showcase-only branch list (web `MOCK_BRANCHES`).
const mockBranches = <AppBranch>[
  AppBranch(id: 'downtown', name: 'Downtown Clinic', org: mockOrg),
  AppBranch(id: 'nasr-city', name: 'Nasr City', org: mockOrg),
  AppBranch(id: 'alexandria', name: 'Alexandria', org: mockOrg),
];

/// Showcase-only signed-in user (web `MOCK_USER`).
const mockUser = AppUserMenuUser(
  name: 'Dr. Sarah Ali',
  role: 'Physician',
  email: 'sarah.ali@aiclinic.health',
);

/// Showcase-only unread notification count (web `MOCK_NOTIFICATION_COUNT`).
const mockNotificationCount = 3;

const _navCounts = <String, int>{
  'patients': 128,
  'appointments': 12,
  'invoices': 5,
};

const _clinicNavGroupsBase = <AppNavGroup>[
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
      AppNavItem(id: 'encounters', label: 'Encounters', icon: Icons.medical_services_outlined),
      AppNavItem(id: 'workspace', label: 'Workspace', icon: Icons.assignment_outlined),
    ],
  ),
  AppNavGroup(
    id: 'operations',
    label: 'Operations',
    items: [
      AppNavItem(id: 'billing', label: 'Billing', icon: Icons.receipt_long_outlined),
      AppNavItem(id: 'invoices', label: 'Invoices', icon: Icons.description_outlined),
      AppNavItem(id: 'services', label: 'Services', icon: Icons.grid_view_outlined),
      AppNavItem(id: 'staff', label: 'Staff', icon: Icons.person_outline),
      AppNavItem(id: 'shifts', label: 'Shifts', icon: Icons.event_outlined),
      AppNavItem(id: 'reports', label: 'Reports', icon: Icons.bar_chart_outlined),
    ],
  ),
];

/// Showcase-only sidebar groups with demo badge counts (web `CLINIC_NAV_GROUPS`).
final clinicNavGroups = <AppNavGroup>[
  for (final group in _clinicNavGroupsBase)
    AppNavGroup(
      id: group.id,
      label: group.label,
      items: [
        for (final item in group.items)
          AppNavItem(
            id: item.id,
            label: item.label,
            icon: item.icon,
            count: _navCounts[item.id],
          ),
      ],
    ),
];

/// Showcase-only sidebar footer items (web `CLINIC_NAV_FOOTER`).
const clinicNavFooter = <AppNavItem>[
  AppNavItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined),
  AppNavItem(id: 'dev', label: 'Dev', icon: Icons.science_outlined),
];
