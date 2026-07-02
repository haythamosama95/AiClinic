import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_detail.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_eligibility.dart';

/// Result of creating a service with initial branch assignments.
class CreateServiceResult {
  const CreateServiceResult({required this.serviceId, required this.assignedBranchIds});

  final String serviceId;
  final List<String> assignedBranchIds;
}

/// Result of adding a catalog service to a draft invoice.
class AddInvoiceItemFromServiceResult {
  const AddInvoiceItemFromServiceResult({
    required this.itemId,
    required this.quantity,
    required this.unitPrice,
    required this.appliedRule,
  });

  final String itemId;
  final String quantity;
  final String unitPrice;
  final String appliedRule;
}

/// Result of configuring a branch row.
class ConfigureServiceBranchResult {
  const ConfigureServiceBranchResult({required this.serviceBranchId, required this.updatedAt});

  final String serviceBranchId;
  final DateTime updatedAt;
}

/// Result of setting or clearing a promotion.
class SetServicePromotionResult {
  const SetServicePromotionResult({required this.serviceBranchId, required this.hasPromotion, required this.updatedAt});

  final String serviceBranchId;
  final bool hasPromotion;
  final DateTime updatedAt;
}

/// Service Catalog RPC wrappers (015).
class ServiceCatalogRepository with AppRpcInvoker {
  ServiceCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260712091000_service_catalog_pricing_rpcs.sql';

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

  Future<ConfigureServiceBranchResult> configureServiceBranch({
    required String serviceId,
    required String branchId,
    required DateTime expectedUpdatedAt,
    required String status,
    String? priceOverride,
  }) async {
    _assertNonEmpty('serviceId', serviceId);
    _assertNonEmpty('branchId', branchId);
    _assertNonEmpty('status', status);

    final params = <String, dynamic>{
      'p_service_id': serviceId.trim(),
      'p_branch_id': branchId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_status': status.trim(),
      'p_price_override': priceOverride?.trim(),
    };

    final result = await invokeRpc('configure_service_branch', params);
    final serviceBranchId = result.data?['service_branch_id']?.toString();
    final updatedAtRaw = result.data?['updated_at']?.toString();
    final updatedAt = updatedAtRaw == null ? null : DateTime.tryParse(updatedAtRaw);
    if (serviceBranchId == null || serviceBranchId.isEmpty || updatedAt == null) {
      throw StateError('configure_service_branch returned an unexpected shape.');
    }

    return ConfigureServiceBranchResult(serviceBranchId: serviceBranchId, updatedAt: updatedAt);
  }

  Future<SetServicePromotionResult> setServicePromotion({
    required String serviceId,
    required String branchId,
    required DateTime expectedUpdatedAt,
    String? promotionPrice,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _assertNonEmpty('serviceId', serviceId);
    _assertNonEmpty('branchId', branchId);

    final clearing = promotionPrice == null && startDate == null && endDate == null;
    if (!clearing && (promotionPrice == null || startDate == null || endDate == null)) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'PROMO_INCOMPLETE',
          errorMessage: 'Promotion requires a price and both start and end dates.',
        ),
      );
    }

    final params = <String, dynamic>{
      'p_service_id': serviceId.trim(),
      'p_branch_id': branchId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_promotion_price': promotionPrice?.trim(),
      'p_start_date': startDate == null ? null : _formatDate(startDate),
      'p_end_date': endDate == null ? null : _formatDate(endDate),
    };

    final result = await invokeRpc('set_service_promotion', params);
    final serviceBranchId = result.data?['service_branch_id']?.toString();
    final hasPromotion = result.data?['has_promotion'] == true;
    final updatedAtRaw = result.data?['updated_at']?.toString();
    final updatedAt = updatedAtRaw == null ? null : DateTime.tryParse(updatedAtRaw);
    if (serviceBranchId == null || serviceBranchId.isEmpty || updatedAt == null) {
      throw StateError('set_service_promotion returned an unexpected shape.');
    }

    return SetServicePromotionResult(
      serviceBranchId: serviceBranchId,
      hasPromotion: hasPromotion,
      updatedAt: updatedAt,
    );
  }

  Future<ServiceEligibility> resolveEffectivePrice({
    required String serviceId,
    required String branchId,
    DateTime? onDate,
  }) async {
    _assertNonEmpty('serviceId', serviceId);
    _assertNonEmpty('branchId', branchId);

    final params = <String, dynamic>{'p_service_id': serviceId.trim(), 'p_branch_id': branchId.trim()};
    if (onDate != null) {
      params['p_on_date'] = _formatDate(onDate);
    }

    final result = await invokeRpc('resolve_effective_service_price', params);
    return ServiceEligibility.fromRpcData(result.data);
  }

  Future<List<EligibleService>> searchEligibleServices({
    required String branchId,
    String query = '',
    DateTime? onDate,
    int limit = 20,
  }) async {
    _assertNonEmpty('branchId', branchId);

    final params = <String, dynamic>{'p_branch_id': branchId.trim(), 'p_query': query.trim(), 'p_limit': limit};
    if (onDate != null) {
      params['p_on_date'] = _formatDate(onDate);
    }

    final result = await invokeRpc('search_eligible_services', params);
    final rawItems = result.data?['items'];
    if (rawItems is! List) {
      return const [];
    }

    final items = <EligibleService>[];
    for (final raw in rawItems) {
      if (raw is Map<String, dynamic>) {
        final item = EligibleService.fromRow(raw);
        if (item != null) {
          items.add(item);
        }
      }
    }
    return items;
  }

  Future<AddInvoiceItemFromServiceResult> addInvoiceItemFromService({
    required String invoiceId,
    required DateTime expectedUpdatedAt,
    required String serviceId,
  }) async {
    _assertNonEmpty('invoiceId', invoiceId);
    _assertNonEmpty('serviceId', serviceId);

    final result = await invokeRpc('add_invoice_item_from_service', {
      'p_invoice_id': invoiceId.trim(),
      'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      'p_service_id': serviceId.trim(),
    });

    final itemId = result.data?['item_id']?.toString();
    final quantity = result.data?['quantity']?.toString();
    final unitPrice = result.data?['unit_price']?.toString();
    final appliedRule = result.data?['applied_rule']?.toString();
    if (itemId == null || itemId.isEmpty || quantity == null || unitPrice == null || appliedRule == null) {
      throw StateError('add_invoice_item_from_service returned an unexpected shape.');
    }

    return AddInvoiceItemFromServiceResult(
      itemId: itemId,
      quantity: quantity,
      unitPrice: unitPrice,
      appliedRule: appliedRule,
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
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
