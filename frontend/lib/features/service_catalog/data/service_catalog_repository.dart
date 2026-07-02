import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';

/// Result of creating a service with initial branch assignments.
class CreateServiceResult {
  const CreateServiceResult({required this.serviceId, required this.assignedBranchIds});

  final String serviceId;
  final List<String> assignedBranchIds;
}

/// Service Catalog RPC wrappers (015).
class ServiceCatalogRepository with AppRpcInvoker {
  ServiceCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260712090500_service_catalog_rpcs.sql';

  @override
  String get rpcLogDomain => 'service_catalog';

  Future<CreateServiceResult> createService({
    required String name,
    required String defaultPrice,
    required GlobalStatus globalStatus,
    required bool assignAllBranches,
    List<String> branchIds = const [],
  }) async {
    _assertNonEmpty('name', name);
    _assertNonEmpty('defaultPrice', defaultPrice);

    final result = await invokeRpc('create_service', {
      'p_name': name.trim(),
      'p_default_price': defaultPrice.trim(),
      'p_global_status': globalStatus.wireValue,
      'p_assign_all_branches': assignAllBranches,
      'p_branch_ids': assignAllBranches ? <String>[] : branchIds,
    });

    final serviceId = result.data?['service_id']?.toString();
    if (serviceId == null || serviceId.isEmpty) {
      throw StateError('create_service returned an unexpected shape.');
    }

    final assignedRaw = result.data?['assigned_branch_ids'];
    final assignedBranchIds = <String>[];
    if (assignedRaw is List) {
      for (final item in assignedRaw) {
        final id = item?.toString();
        if (id != null && id.isNotEmpty) {
          assignedBranchIds.add(id);
        }
      }
    }

    return CreateServiceResult(serviceId: serviceId, assignedBranchIds: assignedBranchIds);
  }

  Future<ServiceDetail> getService({required String serviceId}) async {
    _assertNonEmpty('serviceId', serviceId);

    final result = await invokeRpc('get_service', {'p_service_id': serviceId.trim()});
    final detail = ServiceDetail.fromRpcData(result.data);
    if (detail == null) {
      throw StateError('get_service returned an unexpected shape.');
    }
    return detail;
  }

  Future<List<String>> setBranchAssignment({
    required String serviceId,
    required List<String> branchIds,
    required bool assign,
  }) async {
    _assertNonEmpty('serviceId', serviceId);
    if (branchIds.isEmpty) {
      throw RpcFailure(
        RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'At least one branch ID is required.'),
      );
    }

    final result = await invokeRpc('set_service_branch_assignment', {
      'p_service_id': serviceId.trim(),
      'p_branch_ids': branchIds,
      'p_assign': assign,
    });

    final key = assign ? 'assigned_branch_ids' : 'unassigned_branch_ids';
    final raw = result.data?[key];
    final ids = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final id = item?.toString();
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    return ids;
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }
}

final serviceCatalogRepositoryProvider = Provider<ServiceCatalogRepository>((ref) {
  return ServiceCatalogRepository(ref.watch(supabaseClientProvider));
});
