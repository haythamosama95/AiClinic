import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';

/// Input for `create_staff_account` RPC.
class CreateStaffAccountInput {
  const CreateStaffAccountInput({
    required this.email,
    required this.password,
    required this.fullName,
    required this.role,
    required this.branchIds,
    this.primaryBranchId,
  });

  final String email;
  final String password;
  final String fullName;
  final StaffRole role;
  final List<String> branchIds;
  final String? primaryBranchId;
}

/// Successful staff account creation payload.
class CreateStaffAccountResult {
  const CreateStaffAccountResult({required this.staffMemberId, required this.email, required this.assignedPassword});

  final String staffMemberId;
  final String email;
  final String assignedPassword;
}

/// Successful administrator password reset payload.
class AdminResetStaffPasswordResult {
  const AdminResetStaffPasswordResult({required this.staffMemberId, required this.assignedPassword});

  final String staffMemberId;
  final String assignedPassword;
}

/// Maps provisioning RPC PostgREST failures to [RpcFailure], or returns null to rethrow.
RpcFailure? provisioningRpcFailureFromPostgrest(PostgrestException error, String functionName) {
  if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
    return RpcFailure(
      RpcResult(
        success: false,
        errorCode: 'RPC_NOT_APPLIED',
        errorMessage: 'Database function "$functionName" is missing. Apply backend migrations and restart Supabase.',
      ),
    );
  }
  return null;
}

/// Calls staff provisioning RPCs (`create_staff_account`, `admin_reset_staff_password`).
class ProvisioningRepository {
  ProvisioningRepository(this._client);

  final SupabaseClient _client;

  /// Lists active staff in the caller's organization (RLS-scoped) for password reset picker.
  Future<List<StaffMemberSummary>> listOrgStaffMembers() async {
    final rows = await _client
        .from('staff_members')
        .select('id, full_name, role')
        .eq('is_deleted', false)
        .eq('is_active', true)
        .order('full_name');

    final summaries = <StaffMemberSummary>[];
    for (final row in rows) {
      final summary = StaffMemberSummary.fromRow(Map<String, dynamic>.from(row));
      if (summary != null) {
        summaries.add(summary);
      }
    }

    return summaries;
  }

  /// Loads branch display fields for IDs the caller is allowed to see (org RLS).
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds) async {
    if (branchIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('branches')
        .select('id, name, code, address, phone, maps_url')
        .inFilter('id', branchIds)
        .eq('is_deleted', false)
        .eq('is_active', true);

    final byId = <String, BranchSummary>{};
    for (final row in rows) {
      final summary = BranchSummary.fromRow(Map<String, dynamic>.from(row));
      if (summary != null) {
        byId[summary.id] = summary;
      }
    }

    return [
      for (final id in branchIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input) async {
    final result = await _invoke('create_staff_account', {
      'p_email': input.email.trim(),
      'p_password': input.password,
      'p_full_name': input.fullName.trim(),
      'p_role': input.role.wireValue,
      'p_branch_ids': input.branchIds,
      if (input.primaryBranchId != null) 'p_primary_branch_id': input.primaryBranchId,
    });

    final staffMemberId = result.data?['staff_member_id']?.toString();
    final assignedPassword = result.data?['assigned_password']?.toString();
    if (staffMemberId == null || staffMemberId.isEmpty || assignedPassword == null) {
      throw StateError('Staff account was created but the response was incomplete.');
    }

    return CreateStaffAccountResult(
      staffMemberId: staffMemberId,
      email: input.email.trim().toLowerCase(),
      assignedPassword: assignedPassword,
    );
  }

  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  }) async {
    final result = await _invoke('admin_reset_staff_password', {
      'p_staff_member_id': staffMemberId,
      'p_new_password': newPassword,
    });

    final assignedPassword = result.data?['assigned_password']?.toString();
    if (assignedPassword == null || assignedPassword.isEmpty) {
      throw StateError('Password was reset but the response was incomplete.');
    }

    return AdminResetStaffPasswordResult(staffMemberId: staffMemberId, assignedPassword: assignedPassword);
  }

  Future<RpcResult> _invoke(String functionName, Map<String, dynamic> params) async {
    AppLog.fine('provisioning.rpc.invoke fn=$functionName params=${params.keys.join(',')}');

    try {
      final raw = await _client.rpc(functionName, params: params);
      AppLog.fine('provisioning.rpc.response fn=$functionName type=${raw.runtimeType}');

      final result = RpcResult.fromDynamic(raw);
      if (!result.success) {
        AppLog.warning(
          'provisioning.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
        throw RpcFailure(result);
      }

      return result;
    } on PostgrestException catch (error) {
      AppLog.warning(
        'provisioning.rpc.postgrest_error fn=$functionName code=${error.code} '
        'message=${error.message}',
      );
      final mapped = provisioningRpcFailureFromPostgrest(error, functionName);
      if (mapped != null) {
        throw mapped;
      }
      rethrow;
    } catch (error) {
      AppLog.warning('provisioning.rpc.error fn=$functionName reason=${error.runtimeType} detail=$error');
      rethrow;
    }
  }
}

final provisioningRepositoryProvider = Provider<ProvisioningRepository>((ref) {
  return ProvisioningRepository(ref.watch(supabaseClientProvider));
});
