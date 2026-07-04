import 'package:flutter/material.dart';

/// Sidebar navigation item — mirrors web `NavItem`.
@immutable
class NavItem {
  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.count,
  });

  final String id;
  final String label;
  final IconData icon;
  final int? count;
}

/// Grouped navigation section — mirrors web `NavGroup`.
@immutable
class NavGroup {
  const NavGroup({required this.id, this.label, required this.items});

  final String id;
  final String? label;
  final List<NavItem> items;
}

/// Clinic branch — mirrors web `Branch`.
@immutable
class Branch {
  const Branch({required this.id, required this.name, required this.org});

  final String id;
  final String name;
  final String org;
}

/// Signed-in user for shell chrome — mirrors web `UserMenuUser`.
@immutable
class UserMenuUser {
  const UserMenuUser({
    required this.name,
    this.email,
    this.role,
  });

  final String name;
  final String? email;
  final String? role;
}

const mockOrg = 'AiClinic Health Group';

const mockBranches = <Branch>[
  Branch(id: 'downtown', name: 'Downtown Clinic', org: mockOrg),
  Branch(id: 'nasr-city', name: 'Nasr City', org: mockOrg),
  Branch(id: 'alexandria', name: 'Alexandria', org: mockOrg),
];

const mockUser = UserMenuUser(
  name: 'Dr. Sarah Ali',
  role: 'Physician',
  email: 'sarah.ali@aiclinic.health',
);

const mockNotificationCount = 3;

const clinicNavGroups = <NavGroup>[
  NavGroup(
    id: 'main',
    items: [
      NavItem(id: 'home', label: 'Home', icon: Icons.home_outlined),
      NavItem(id: 'dashboard', label: 'Dashboard', icon: Icons.grid_view_outlined),
    ],
  ),
  NavGroup(
    id: 'clinical',
    label: 'Clinical',
    items: [
      NavItem(
        id: 'patients',
        label: 'Patients',
        icon: Icons.people_outline,
        count: 128,
      ),
      NavItem(
        id: 'appointments',
        label: 'Appointments',
        icon: Icons.calendar_today_outlined,
        count: 12,
      ),
      NavItem(
        id: 'encounters',
        label: 'Encounters',
        icon: Icons.medical_services_outlined,
      ),
      NavItem(
        id: 'workspace',
        label: 'Workspace',
        icon: Icons.assignment_outlined,
      ),
    ],
  ),
  NavGroup(
    id: 'operations',
    label: 'Operations',
    items: [
      NavItem(id: 'billing', label: 'Billing', icon: Icons.receipt_long_outlined),
      NavItem(
        id: 'invoices',
        label: 'Invoices',
        icon: Icons.description_outlined,
        count: 5,
      ),
      NavItem(
        id: 'services',
        label: 'Services',
        icon: Icons.grid_view_outlined,
      ),
      NavItem(id: 'staff', label: 'Staff', icon: Icons.person_outline),
      NavItem(id: 'shifts', label: 'Shifts', icon: Icons.calendar_today_outlined),
      NavItem(id: 'reports', label: 'Reports', icon: Icons.bar_chart_outlined),
    ],
  ),
];

const clinicNavFooter = <NavItem>[
  NavItem(id: 'settings', label: 'Settings', icon: Icons.settings_outlined),
  NavItem(id: 'dev', label: 'Dev', icon: Icons.science_outlined),
];

final allNavItems = <NavItem>[
  ...clinicNavGroups.expand((group) => group.items),
  ...clinicNavFooter,
];
