import 'package:flutter/foundation.dart';

/// Staff roles aligned with PostgreSQL `staff_role` enum.
enum StaffRole {
  owner,
  administrator,
  doctor,
  receptionist,
  labStaff;

  static StaffRole? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'owner' => StaffRole.owner,
      'administrator' => StaffRole.administrator,
      'doctor' => StaffRole.doctor,
      'receptionist' => StaffRole.receptionist,
      'lab_staff' => StaffRole.labStaff,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    StaffRole.owner => 'owner',
    StaffRole.administrator => 'administrator',
    StaffRole.doctor => 'doctor',
    StaffRole.receptionist => 'receptionist',
    StaffRole.labStaff => 'lab_staff',
  };
}

@immutable
/// Staff profile loaded after authentication.
class StaffProfile {
  const StaffProfile({
    required this.staffMemberId,
    required this.fullName,
    required this.role,
    required this.isBootstrapAdmin,
    required this.isActive,
  });

  final String staffMemberId;
  final String fullName;
  final StaffRole role;
  final bool isBootstrapAdmin;
  final bool isActive;
}

@immutable
/// In-memory authenticated session context for routing and permission checks.
class AuthSessionContext {
  const AuthSessionContext({
    required this.staffProfile,
    required this.organizationId,
    required this.branchIds,
    required this.activeBranchId,
    required this.permissions,
    required this.setupRequired,
  });

  final StaffProfile staffProfile;
  final String? organizationId;
  final List<String> branchIds;
  final String? activeBranchId;
  final Set<String> permissions;
  final bool setupRequired;

  bool get hasBranchAssignment => branchIds.isNotEmpty;

  AuthSessionContext copyWith({
    StaffProfile? staffProfile,
    String? organizationId,
    List<String>? branchIds,
    String? activeBranchId,
    Set<String>? permissions,
    bool? setupRequired,
  }) {
    return AuthSessionContext(
      staffProfile: staffProfile ?? this.staffProfile,
      organizationId: organizationId ?? this.organizationId,
      branchIds: branchIds ?? this.branchIds,
      activeBranchId: activeBranchId ?? this.activeBranchId,
      permissions: permissions ?? this.permissions,
      setupRequired: setupRequired ?? this.setupRequired,
    );
  }
}
