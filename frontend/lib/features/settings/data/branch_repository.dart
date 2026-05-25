import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/settings_rpc_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';

/// Branch list reads (RLS) and lifecycle mutations (RPC).
class BranchRepositoryImpl with SettingsRpcInvoker implements BranchRepository {
  BranchRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get settingsRpcClient => _client;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    final base = _client
        .from('branches')
        .select('id, name, code, address, phone, maps_url, is_active')
        .eq('organization_id', organizationId)
        .eq('is_deleted', false);

    final List<dynamic> rows;
    switch (filter) {
      case BranchListFilter.active:
        rows = await base.eq('is_active', true).order('name');
      case BranchListFilter.inactive:
        rows = await base.eq('is_active', false).order('name');
      case BranchListFilter.all:
        rows = await base.order('name');
    }
    final items = <BranchListItem>[];
    for (final row in rows) {
      final item = BranchListItem.fromRow(Map<String, dynamic>.from(row));
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  @override
  Future<String> createBranch(CreateBranchInput input) async {
    final name = input.name.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Branch name is required.'),
      );
    }

    final result = await invokeSettingsRpc('manage_create_branch', {
      'p_name': name,
      if (input.code != null) 'p_code': input.code!.trim(),
      if (input.address != null) 'p_address': input.address!.trim(),
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.mapsUrl != null) 'p_maps_url': input.mapsUrl!.trim(),
    });

    final branchId = result.data?['branch_id']?.toString();
    if (branchId == null || branchId.isEmpty) {
      throw StateError('Branch was created but no branch_id was returned.');
    }
    return branchId;
  }

  @override
  Future<String> updateBranch(UpdateBranchInput input) async {
    final name = input.name.trim();
    if (name.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Branch name is required.'),
      );
    }

    final result = await invokeSettingsRpc('update_branch', {
      'p_branch_id': input.branchId,
      'p_name': name,
      if (input.code != null) 'p_code': input.code!.trim(),
      if (input.address != null) 'p_address': input.address!.trim(),
      if (input.phone != null) 'p_phone': input.phone!.trim(),
      if (input.mapsUrl != null) 'p_maps_url': input.mapsUrl!.trim(),
    });

    return result.data?['branch_id']?.toString() ?? input.branchId;
  }

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) {
    return invokeSettingsRpc('set_branch_active', {'p_branch_id': branchId, 'p_is_active': isActive});
  }
}

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepositoryImpl(ref.watch(supabaseClientProvider));
});
