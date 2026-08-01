import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/permission_matrix_view.dart';

/// Permission keys aligned with `roles_permissions` seed (settings → Staff roles).
typedef PermissionKey = String;

const kPermissionKeys = <PermissionKey>[
  'settings.manage_staff',
  'settings.manage_branches',
  'settings.billing.manage',
  'patients.view',
  'patients.create',
  'patients.edit',
  'patients.delete',
  'appointments.create',
  'appointments.cancel',
  'appointments.read',
  'visits.create',
  'visits.edit_soap',
  'visits.upload_attachment',
  'invoices.view',
  'invoices.create',
  'invoices.apply_discount',
  'invoices.void',
  'payments.record',
  'payments.refund',
  'insurance.manage',
  'shifts.manage',
  'services.view',
  'services.manage',
  'analytics.view',
  'ai.access',
];

typedef RoleGrantsMap = Map<StaffRole, Set<PermissionKey>>;

const _defaultRoleGrants = <StaffRole, Set<PermissionKey>>{
  StaffRole.administrator: {
    'settings.manage_staff',
    'settings.manage_branches',
    'settings.billing.manage',
    'patients.view',
    'patients.create',
    'patients.edit',
    'patients.delete',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'visits.create',
    'visits.edit_soap',
    'visits.upload_attachment',
    'invoices.view',
    'invoices.create',
    'invoices.apply_discount',
    'invoices.void',
    'payments.record',
    'payments.refund',
    'insurance.manage',
    'shifts.manage',
    'services.view',
    'services.manage',
    'analytics.view',
    'ai.access',
  },
  StaffRole.doctor: {
    'patients.view',
    'patients.create',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'visits.create',
    'visits.edit_soap',
    'visits.upload_attachment',
    'ai.access',
  },
  StaffRole.receptionist: {
    'patients.view',
    'appointments.create',
    'appointments.cancel',
    'appointments.read',
    'invoices.view',
    'invoices.create',
    'payments.record',
  },
  StaffRole.labStaff: {
    'patients.view',
    'appointments.read',
    'visits.upload_attachment',
  },
};

RoleGrantsMap createDefaultRoleGrants() {
  return {
    for (final entry in _defaultRoleGrants.entries) entry.key: Set<PermissionKey>.from(entry.value),
  };
}

RoleGrantsMap cloneRoleGrants(RoleGrantsMap grants) {
  return {for (final entry in grants.entries) entry.key: Set<PermissionKey>.from(entry.value)};
}

bool roleGrantsEqual(RoleGrantsMap a, RoleGrantsMap b) {
  for (final role in StaffRole.values) {
    final setA = a[role] ?? const <PermissionKey>{};
    final setB = b[role] ?? const <PermissionKey>{};
    if (setA.length != setB.length) {
      return false;
    }
    for (final key in setA) {
      if (!setB.contains(key)) {
        return false;
      }
    }
  }
  return true;
}

bool isPermissionGrantedInMap(RoleGrantsMap grants, StaffRole role, PermissionKey key) {
  return grants[role]?.contains(key) ?? false;
}

/// `settings.billing.manage` can only be granted to administrators.
bool canTogglePermissionGrant({
  required StaffRole role,
  required String permissionKey,
  required bool nextGranted,
}) {
  if (permissionKey == 'settings.billing.manage' && nextGranted && role != StaffRole.administrator) {
    return false;
  }
  return true;
}

String permissionCategory(PermissionKey key) => PermissionMatrixView.permissionCategory(key);

String categoryLabel(String category) => PermissionMatrixView.categoryLabel(category);

String permissionLabel(PermissionKey key) => PermissionMatrixView.permissionLabel(key);

List<PermissionCategoryGroup> permissionCategoryGroups() {
  final byCategory = <String, List<PermissionKey>>{};
  for (final key in kPermissionKeys) {
    final category = permissionCategory(key);
    byCategory.putIfAbsent(category, () => []).add(key);
  }

  final categories = byCategory.keys.toList()..sort();
  return [
    for (final category in categories)
      PermissionCategoryGroup(category: category, permissionKeys: byCategory[category]!..sort()),
  ];
}
