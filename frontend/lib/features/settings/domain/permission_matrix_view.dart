import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:flutter/foundation.dart';

/// One permission category with keys sorted for matrix display.
@immutable
class PermissionCategoryGroup {
  const PermissionCategoryGroup({required this.category, required this.permissionKeys});

  final String category;
  final List<String> permissionKeys;
}

/// Matrix rows grouped by permission key with grant lookup per role (V1-2).
@immutable
class PermissionMatrixView {
  const PermissionMatrixView({required this.permissionKeys, required this.grantsByRoleAndKey});

  static const displayRoles = <StaffRole>[
    StaffRole.administrator,
    StaffRole.doctor,
    StaffRole.receptionist,
    StaffRole.labStaff,
  ];

  final List<String> permissionKeys;
  final Map<String, Map<StaffRole, bool>> grantsByRoleAndKey;

  static PermissionMatrixView fromRows(List<PermissionMatrixRow> rows) {
    final grants = <String, Map<StaffRole, bool>>{};
    for (final row in rows) {
      grants.putIfAbsent(row.permissionKey, () => {});
      grants[row.permissionKey]![row.role] = row.isGranted;
    }

    final keys = grants.keys.toList()..sort();
    for (final permissionKey in keys) {
      final roleGrants = grants.putIfAbsent(permissionKey, () => {});
      for (final role in displayRoles) {
        roleGrants.putIfAbsent(role, () => false);
      }
    }

    return PermissionMatrixView(permissionKeys: keys, grantsByRoleAndKey: grants);
  }

  /// Permission keys grouped by the segment before the first dot (e.g. `patients.view` → `patients`).
  List<PermissionCategoryGroup> get categoryGroups {
    final byCategory = <String, List<String>>{};
    for (final key in permissionKeys) {
      final category = permissionCategory(key);
      byCategory.putIfAbsent(category, () => []).add(key);
    }

    final categories = byCategory.keys.toList()..sort();
    return [
      for (final category in categories)
        PermissionCategoryGroup(category: category, permissionKeys: byCategory[category]!..sort()),
    ];
  }

  static String permissionCategory(String permissionKey) {
    final dot = permissionKey.indexOf('.');
    return dot == -1 ? permissionKey : permissionKey.substring(0, dot);
  }

  /// Display label for a permission row (segment after the first dot).
  static String permissionLabel(String permissionKey) {
    final dot = permissionKey.indexOf('.');
    final action = dot == -1 ? permissionKey : permissionKey.substring(dot + 1);
    if (action.isEmpty) {
      return permissionKey;
    }
    return action
        .split('_')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  /// Whether this role/permission pair is shown in the configurable matrix.
  bool hasDefinedCell(StaffRole role, String permissionKey) {
    return permissionKeys.contains(permissionKey) && displayRoles.contains(role);
  }

  static String categoryLabel(String category) => switch (category) {
    'ai' => 'AI',
    _ => category.isEmpty ? category : '${category[0].toUpperCase()}${category.substring(1)}',
  };

  bool isGranted(StaffRole role, String permissionKey) {
    return grantsByRoleAndKey[permissionKey]?[role] ?? false;
  }

  PermissionMatrixView withGrant({required StaffRole role, required String permissionKey, required bool isGranted}) {
    if (!hasDefinedCell(role, permissionKey)) {
      return this;
    }

    final nextGrants = <String, Map<StaffRole, bool>>{};
    for (final entry in grantsByRoleAndKey.entries) {
      nextGrants[entry.key] = Map<StaffRole, bool>.from(entry.value);
    }
    nextGrants.putIfAbsent(permissionKey, () => {for (final displayRole in displayRoles) displayRole: false});
    for (final displayRole in displayRoles) {
      nextGrants[permissionKey]!.putIfAbsent(displayRole, () => false);
    }
    nextGrants[permissionKey]![role] = isGranted;

    final keys = nextGrants.keys.toList()..sort();
    return PermissionMatrixView(permissionKeys: keys, grantsByRoleAndKey: nextGrants);
  }

  /// Cells whose grant differs from [other] across the full role × permission grid.
  Iterable<({StaffRole role, String permissionKey, bool isGranted})> changesFrom(PermissionMatrixView other) sync* {
    for (final permissionKey in permissionKeys) {
      for (final role in displayRoles) {
        if (!hasDefinedCell(role, permissionKey)) {
          continue;
        }
        final next = isGranted(role, permissionKey);
        if (next != other.isGranted(role, permissionKey)) {
          yield (role: role, permissionKey: permissionKey, isGranted: next);
        }
      }
    }
  }

  static String roleLabel(StaffRole role) => switch (role) {
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! PermissionMatrixView || !listEquals(permissionKeys, other.permissionKeys)) {
      return false;
    }

    final allKeys = {...permissionKeys, ...other.permissionKeys};
    for (final permissionKey in allKeys) {
      for (final role in displayRoles) {
        if (!hasDefinedCell(role, permissionKey) && !other.hasDefinedCell(role, permissionKey)) {
          continue;
        }
        if (isGranted(role, permissionKey) != other.isGranted(role, permissionKey)) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = Object.hashAll(permissionKeys);
    for (final permissionKey in permissionKeys) {
      for (final role in displayRoles) {
        if (!hasDefinedCell(role, permissionKey)) {
          continue;
        }
        hash = Object.hash(hash, role, isGranted(role, permissionKey));
      }
    }
    return hash;
  }
}
