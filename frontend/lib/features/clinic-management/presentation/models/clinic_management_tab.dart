import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:flutter/material.dart';

/// Clinic Management page tab identifiers (web `TAB_ITEMS` ids).
enum ClinicManagementTab {
  organization('organization', 'Organization', Icons.apartment),
  branches('branches', 'Branches', Icons.location_on),
  staff('staff', 'Staff', Icons.group),
<<<<<<< HEAD
  roles('roles', 'Roles', Icons.shield);
=======
  roles('roles', 'Roles', Icons.shield),
  services('services', 'Services', Icons.medical_services_outlined),
  settings('settings', 'Settings', Icons.settings_outlined);
>>>>>>> master

  const ClinicManagementTab(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static ClinicManagementTab? byId(String id) {
    for (final tab in ClinicManagementTab.values) {
      if (tab.id == id) {
        return tab;
      }
    }
    return null;
  }
}

<<<<<<< HEAD
/// Full tab catalog in display order (Organization → Branches → Staff → Roles).
=======
/// Full tab catalog in display order (Organization → Branches → Staff → Roles → Services → Settings).
>>>>>>> master
const clinicManagementTabs = ClinicManagementTab.values;

/// Tabs visible for the current session (§5 Phase 2 wiring).
List<ClinicManagementTab> clinicManagementTabsFor(AuthSessionState auth) {
  return [
    for (final tab in clinicManagementTabs)
      if (_isTabVisible(tab, auth)) tab,
  ];
}

bool _isTabVisible(ClinicManagementTab tab, AuthSessionState auth) {
  return switch (tab) {
    ClinicManagementTab.organization =>
      AuthRouteGuard.canAccessOrganizationSettings(auth) || AuthRouteGuard.canAccessBranchManagement(auth),
    ClinicManagementTab.branches => AuthRouteGuard.canAccessBranchManagement(auth),
    ClinicManagementTab.staff => AuthRouteGuard.canAccessStaffManagement(auth),
    ClinicManagementTab.roles => AuthRouteGuard.canAccessPermissionMatrix(auth),
<<<<<<< HEAD
=======
    ClinicManagementTab.services => AuthRouteGuard.canAccessServiceCatalogList(auth),
    ClinicManagementTab.settings => AuthRouteGuard.canAccessBillingSettings(auth),
>>>>>>> master
  };
}
