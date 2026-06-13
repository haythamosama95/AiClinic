import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';

/// Staff administration reads (RLS) and lifecycle RPCs.
class StaffAdminRepositoryImpl with AppRpcInvoker, SettingsRpcInvoker implements StaffAdminRepository {
  StaffAdminRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    final base = _client.from('staff_members').select('id, full_name, role, phone, is_active').eq('is_deleted', false);

    final List<dynamic> rows;
    switch (filter) {
      case StaffListFilter.active:
        rows = await base.eq('is_active', true).order('full_name', ascending: true);
      case StaffListFilter.inactive:
        rows = await base.eq('is_active', false).order('full_name', ascending: true);
      case StaffListFilter.all:
        rows = await base.order('full_name', ascending: true);
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

    final staffIds = items.map((s) => s.id).toList();
    final branchesByStaff = await _loadBranchesByStaffId(staffIds);
    final usernamesByStaff = await _loadUsernamesByStaffId(staffIds);
    final enriched = [
      for (final item in items)
        item.copyWith(branches: branchesByStaff[item.id] ?? const [], username: usernamesByStaff[item.id]),
    ];
    enriched.sort(StaffListItem.compareByFullName);
    return enriched;
  }

  @override
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
    final detail = StaffMemberDetail.fromRow(Map<String, dynamic>.from(row));
    if (detail == null) {
      return null;
    }

    final usernames = await _loadUsernamesByStaffId([staffMemberId]);
    final username = usernames[staffMemberId];
    if (username == null) {
      return detail;
    }

    return StaffMemberDetail(
      id: detail.id,
      fullName: detail.fullName,
      role: detail.role,
      isActive: detail.isActive,
      branchIds: detail.branchIds,
      phone: detail.phone,
      primaryBranchId: detail.primaryBranchId,
      username: username,
    );
  }

  Future<Map<String, List<StaffBranchLabel>>> _loadBranchesByStaffId(List<String> staffIds) async {
    if (staffIds.isEmpty) {
      return const {};
    }

    final rows = await _client
        .from('staff_branch_assignments')
        .select('staff_member_id, branch_id, is_primary, branches(name)')
        .inFilter('staff_member_id', staffIds)
        .eq('is_deleted', false);

    final map = <String, List<StaffBranchLabel>>{};
    for (final row in rows) {
      final staffId = row['staff_member_id']?.toString();
      if (staffId == null || staffId.isEmpty) {
        continue;
      }
      final branchId = row['branch_id']?.toString();
      final branch = row['branches'];
      String? name;
      if (branch is Map) {
        name = branch['name']?.toString().trim();
      }
      if (name == null || name.isEmpty) {
        continue;
      }
      final isPrimary = row['is_primary'] == true || row['is_primary']?.toString().toLowerCase() == 'true';
      map
          .putIfAbsent(staffId, () => <StaffBranchLabel>[])
          .add(StaffBranchLabel(id: branchId, name: name, isPrimary: isPrimary));
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        if (a.isPrimary != b.isPrimary) {
          return a.isPrimary ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
    }

    return map;
  }

  Future<Map<String, String>> _loadUsernamesByStaffId(List<String> staffIds) async {
    if (staffIds.isEmpty) {
      return const {};
    }

    try {
      final rows = await _client.rpc('staff_login_usernames', params: {'p_staff_ids': staffIds});
      if (rows is! List) {
        return const {};
      }

      final map = <String, String>{};
      for (final row in rows) {
        if (row is! Map) {
          continue;
        }
        final staffId = row['staff_member_id']?.toString();
        final username = row['username']?.toString().trim();
        if (staffId != null && staffId.isNotEmpty && username != null && username.isNotEmpty) {
          map[staffId] = username;
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  @override
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

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) {
    return invokeSettingsRpc('set_staff_active', {'p_staff_member_id': staffMemberId, 'p_is_active': isActive});
  }
}

final staffAdminRepositoryProvider = Provider<StaffAdminRepository>((ref) {
  return StaffAdminRepositoryImpl(ref.watch(supabaseClientProvider));
});
