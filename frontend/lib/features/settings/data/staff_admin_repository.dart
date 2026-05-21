import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';

/// Filter for staff list queries.
enum StaffListFilter { active, inactive, all }

/// Input for [update_staff_member] RPC.
class UpdateStaffMemberInput {
  const UpdateStaffMemberInput({
    required this.staffMemberId,
    required this.fullName,
    required this.role,
    required this.branchIds,
    this.phone,
    this.primaryBranchId,
    this.isActive,
  });

  final String staffMemberId;
  final String fullName;
  final StaffRole role;
  final List<String> branchIds;
  final String? phone;
  final String? primaryBranchId;
  final bool? isActive;
}

/// Staff administration reads (RLS) and lifecycle RPCs.
class StaffAdminRepository with SettingsRpcInvoker {
  StaffAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    final base = _client.from('staff_members').select('id, full_name, role, phone, is_active').eq('is_deleted', false);

    final List<dynamic> rows;
    switch (filter) {
      case StaffListFilter.active:
        rows = await base.eq('is_active', true).order('full_name');
      case StaffListFilter.inactive:
        rows = await base.eq('is_active', false).order('full_name');
      case StaffListFilter.all:
        rows = await base.order('full_name');
    }
    final items = <StaffListItem>[];
    for (final row in rows) {
      final item = StaffListItem.fromRow(Map<String, dynamic>.from(row));
      if (item != null) {
        items.add(item);
      }
    }

    if (items.isEmpty) {
      return items;
    }

    final branchNamesByStaff = await _loadBranchNamesByStaffId(items.map((s) => s.id).toList());
    return [for (final item in items) item.copyWith(branchNames: branchNamesByStaff[item.id] ?? const [])];
  }

  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) async {
    final row = await _client
        .from('staff_members')
        .select('id, full_name, role, phone, is_active, staff_branch_assignments(branch_id, is_primary, is_deleted)')
        .eq('id', staffMemberId)
        .eq('is_deleted', false)
        .maybeSingle();

    if (row == null) {
      return null;
    }
    return StaffMemberDetail.fromRow(Map<String, dynamic>.from(row));
  }

  /// Whether the organization already has at least one owner account.
  Future<bool> organizationHasOwner() async {
    final rows = await _client
        .from('staff_members')
        .select('id')
        .eq('role', StaffRole.owner.wireValue)
        .eq('is_deleted', false)
        .eq('is_active', true);
    return rows.isNotEmpty;
  }

  Future<Map<String, List<String>>> _loadBranchNamesByStaffId(List<String> staffIds) async {
    if (staffIds.isEmpty) {
      return const {};
    }

    final rows = await _client
        .from('staff_branch_assignments')
        .select('staff_member_id, branches(name)')
        .inFilter('staff_member_id', staffIds)
        .eq('is_deleted', false);

    final map = <String, List<String>>{};
    for (final row in rows) {
      final staffId = row['staff_member_id']?.toString();
      if (staffId == null || staffId.isEmpty) {
        continue;
      }
      final branch = row['branches'];
      String? name;
      if (branch is Map) {
        name = branch['name']?.toString().trim();
      }
      if (name == null || name.isEmpty) {
        continue;
      }
      map.putIfAbsent(staffId, () => <String>[]).add(name);
    }
    return map;
  }

  Future<String> updateStaffMember(UpdateStaffMemberInput input) async {
    final fullName = input.fullName.trim();
    if (fullName.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Full name is required.'),
      );
    }
    if (input.branchIds.isEmpty) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'At least one branch assignment is required.',
        ),
      );
    }

    final result = await invokeSettingsRpc('update_staff_member', {
      'p_staff_member_id': input.staffMemberId,
      'p_full_name': fullName,
      'p_role': input.role.wireValue,
      'p_branch_ids': input.branchIds,
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.primaryBranchId != null) 'p_primary_branch_id': input.primaryBranchId,
      if (input.isActive != null) 'p_is_active': input.isActive,
    });

    return result.data?['staff_member_id']?.toString() ?? input.staffMemberId;
  }

  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return invokeSettingsRpc('set_staff_active', {'p_staff_member_id': staffMemberId, 'p_is_active': isActive});
  }
}

final staffAdminRepositoryProvider = Provider<StaffAdminRepository>((ref) {
  return StaffAdminRepository(ref.watch(supabaseClientProvider));
});
