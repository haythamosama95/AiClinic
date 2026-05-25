import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Loads [AuthSessionContext] from a Supabase [Session] by decoding JWT claims,
/// querying the staff profile, resolving the primary branch, and loading
/// granted permissions.
///
/// Extracted from [AuthSessionNotifier] for testability and single-responsibility.
class SessionContextLoader {
  const SessionContextLoader(this._client, this._permissionRepository);

  final SupabaseClient _client;
  final PermissionRepository _permissionRepository;

  Future<AuthSessionContext> load(Session session) async {
    final claims = decodeAccessTokenClaims(session.accessToken);
    final staffMemberId = claims['staff_member_id']?.toString();

    if (staffMemberId == null) {
      throw StateError('Authenticated session is missing staff claims.');
    }

    final staffRow = await _client
        .from('staff_members')
        .select('id, full_name, role, is_bootstrap_admin, is_active')
        .eq('id', staffMemberId)
        .maybeSingle();

    if (staffRow == null) {
      throw StateError('No active staff profile is linked to this account.');
    }

    if (staffRow['is_active'] != true) {
      throw StateError('This staff account is inactive. Contact your clinic administrator.');
    }

    final role =
        StaffRole.tryParse(staffRow['role']?.toString()) ?? StaffRole.tryParse(claims['staff_role']?.toString());
    if (role == null) {
      throw StateError('Authenticated session is missing a valid staff role.');
    }

    final branchIdsRaw = claims['branch_ids']?.toString() ?? '';
    final branchIds = branchIdsRaw.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();

    final permissions = await _permissionRepository.loadGrantedPermissions(role);
    final setupRequired = claims['setup_required'] == true || claims['setup_required']?.toString() == 'true';

    String? primaryBranchId;
    if (branchIds.isNotEmpty) {
      final primaryRow = await _client
          .from('staff_branch_assignments')
          .select('branch_id')
          .eq('staff_member_id', staffMemberId)
          .eq('is_primary', true)
          .maybeSingle();
      primaryBranchId = primaryRow?['branch_id']?.toString();
      if (primaryBranchId == null || !branchIds.contains(primaryBranchId)) {
        primaryBranchId = branchIds.first;
      }
    }

    return AuthSessionContext(
      staffProfile: StaffProfile(
        staffMemberId: staffMemberId,
        fullName: staffRow['full_name']?.toString() ?? 'Staff',
        role: role,
        isBootstrapAdmin: staffRow['is_bootstrap_admin'] == true,
        isActive: staffRow['is_active'] == true,
      ),
      organizationId: claims['organization_id']?.toString(),
      branchIds: branchIds,
      activeBranchId: primaryBranchId,
      permissions: permissions,
      setupRequired: setupRequired,
    );
  }

  /// Classifies the failure reason for structured log messages.
  static String contextFailureReason(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('missing staff claims')) {
      return 'missing_staff_claims';
    }
    if (message.contains('inactive')) {
      return 'inactive_staff';
    }
    if (message.contains('no active staff profile')) {
      return 'staff_profile_missing';
    }
    return error.runtimeType.toString();
  }
}
