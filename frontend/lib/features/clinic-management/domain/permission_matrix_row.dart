import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter/foundation.dart';

/// One grant cell in the role permissions matrix (V1-2).
@immutable
class PermissionMatrixRow {
  const PermissionMatrixRow({required this.role, required this.permissionKey, required this.isGranted});

  final StaffRole role;
  final String permissionKey;
  final bool isGranted;

  static PermissionMatrixRow? fromRow(Map<String, dynamic> row) {
    final role = StaffRole.tryParse(row['role']?.toString());
    final permissionKey = row['permission_key']?.toString().trim();
    if (role == null || permissionKey == null || permissionKey.isEmpty) {
      return null;
    }

    return PermissionMatrixRow(role: role, permissionKey: permissionKey, isGranted: _parseIsGranted(row['is_granted']));
  }

  static bool _parseIsGranted(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == 't' || text == '1';
  }

  PermissionMatrixRow copyWith({StaffRole? role, String? permissionKey, bool? isGranted}) {
    return PermissionMatrixRow(
      role: role ?? this.role,
      permissionKey: permissionKey ?? this.permissionKey,
      isGranted: isGranted ?? this.isGranted,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PermissionMatrixRow &&
            runtimeType == other.runtimeType &&
            role == other.role &&
            permissionKey == other.permissionKey &&
            isGranted == other.isGranted;
  }

  @override
  int get hashCode => Object.hash(role, permissionKey, isGranted);
}
