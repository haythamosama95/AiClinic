import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/repositories/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Loads [AuthSessionContext] from a Supabase [Session] by decoding JWT claims,
/// querying the staff profile, resolving the primary branch, and loading
/// granted permissions.
///
/// Extracted from [AuthSessionNotifier] for testability and single-responsibility.
class SessionContextLoader {
  const SessionContextLoader(
    this._client,
    this._permissionRepository, {
    Duration queryTimeout = const Duration(seconds: 8),
    Duration retryBackoff = const Duration(milliseconds: 500),
  }) : _queryTimeout = queryTimeout,
       _retryBackoff = retryBackoff;

  static const defaultQueryTimeout = Duration(seconds: 8);
  static const defaultRetryBackoff = Duration(milliseconds: 500);

  final SupabaseClient _client;
  final PermissionRepository _permissionRepository;
  final Duration _queryTimeout;
  final Duration _retryBackoff;

  Future<AuthSessionContext> load(Session session) async {
    final decodeResult = decodeAccessTokenClaims(session.accessToken);
    switch (decodeResult) {
      case AccessTokenClaimsExpired():
        throw StateError('Authenticated session access token has expired.');
      case AccessTokenClaimsInvalid():
        throw StateError('Authenticated session has invalid access token claims.');
      case AccessTokenClaimsSuccess(:final claims):
        return _loadFromClaims(claims);
    }
  }

  Future<AuthSessionContext> _loadFromClaims(Map<String, dynamic> claims) async {
    final staffMemberId = claims['staff_member_id']?.toString();

    if (staffMemberId == null) {
      throw StateError('Authenticated session is missing staff claims.');
    }

    final staffRow = await _withQueryTimeoutAndRetry(
      () async => await _client
          .from('staff_members')
          .select('id, full_name, role, is_bootstrap_admin, is_active')
          .eq('id', staffMemberId)
          .maybeSingle(),
    );

    if (staffRow == null) {
      throw StateError('No active staff profile is linked to this account.');
    }

    if (staffRow['is_active'] != true) {
      throw StateError('This staff account is inactive. Contact your clinic administrator.');
    }

    // JWT `staff_role` claim contract (from `get_custom_claims`):
    // - Wire values: `administrator`, `doctor`, `receptionist`, `lab_staff` (snake_case).
    // - Normalized to lowercase before matching; camelCase enum names are not accepted.
    // - Used as fallback when `staff_members.role` is absent or unparsable.
    final role = resolveStaffRole(
      staffRowRole: staffRow['role']?.toString(),
      claimStaffRole: claims['staff_role']?.toString(),
    );
    if (role == null) {
      throw StateError('Authenticated session is missing a valid staff role.');
    }

    final branchIds = parseBranchIdsFromClaim(claims['branch_ids']?.toString() ?? '');

    final permissions = await _withQueryTimeoutAndRetry(() async => await _permissionRepository.loadGrantedPermissions(role));
    final organizationId = claims['organization_id']?.toString();
    final hasOrganization = organizationId != null && organizationId.isNotEmpty;
    final claimSetupRequired = claims['setup_required'] == true || claims['setup_required']?.toString() == 'true';
    final setupRequired = claimSetupRequired || !hasOrganization;

    String? primaryBranchId;
    if (branchIds.isNotEmpty) {
      final primaryRow = await _withQueryTimeoutAndRetry(
        () async => await _client
            .from('staff_branch_assignments')
            .select('branch_id')
            .eq('staff_member_id', staffMemberId)
            .eq('is_primary', true)
            .maybeSingle(),
      );
      primaryBranchId = primaryRow?['branch_id']?.toString();
      if (primaryBranchId == null || !branchIds.contains(primaryBranchId)) {
        primaryBranchId = branchIds.first;
      }
    }

    String? organizationTimezone;
    if (hasOrganization) {
      final orgRow = await _withQueryTimeoutAndRetry(
        () async => await _client.from('organizations').select('timezone').eq('id', organizationId).maybeSingle(),
      );
      organizationTimezone = orgRow?['timezone']?.toString();
    }

    return AuthSessionContext(
      staffProfile: StaffProfile(
        staffMemberId: staffMemberId,
        fullName: staffRow['full_name']?.toString() ?? 'Staff',
        role: role,
        isBootstrapAdmin: staffRow['is_bootstrap_admin'] == true,
        isActive: staffRow['is_active'] == true,
      ),
      organizationId: organizationId,
      branchIds: branchIds,
      activeBranchId: primaryBranchId,
      permissions: permissions,
      setupRequired: setupRequired,
      organizationTimezone: organizationTimezone,
    );
  }

  Future<T> _withQueryTimeoutAndRetry<T>(Future<T> Function() run) async {
    try {
      return await run().timeout(_queryTimeout);
    } catch (_) {
      await Future<void>.delayed(_retryBackoff);
      return await run().timeout(_queryTimeout);
    }
  }

  /// Parses comma-separated `branch_ids` JWT claim values.
  ///
  /// Filters empty segments and JS-style `"null"` / `"undefined"` string literals
  /// that some claim generators emit when a branch list is absent.
  @visibleForTesting
  static List<String> parseBranchIdsFromClaim(String branchIdsRaw) {
    return branchIdsRaw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !_isPlaceholderBranchId(value))
        .toList();
  }

  static bool _isPlaceholderBranchId(String value) {
    final normalized = value.toLowerCase();
    return normalized == 'null' || normalized == 'undefined';
  }

  /// Resolves [StaffRole] from the staff row, falling back to the JWT claim.
  @visibleForTesting
  static StaffRole? resolveStaffRole({String? staffRowRole, String? claimStaffRole}) {
    return StaffRole.tryParse(staffRowRole) ?? StaffRole.tryParse(claimStaffRole);
  }

  /// Classifies the failure reason for structured log messages.
  static String contextFailureReason(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('access token has expired')) {
      return 'expired_access_token';
    }
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
