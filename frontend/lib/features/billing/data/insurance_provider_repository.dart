import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/billing/domain/insurance_provider.dart';

/// Insurance provider catalog RPC wrappers (V1-6).
class InsuranceProviderRepository with AppRpcInvoker {
  InsuranceProviderRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260605180000_billing.sql';

  @override
  String get rpcLogDomain => 'billing.insurance';

  Future<List<InsuranceProvider>> listProviders({bool onlyActive = true}) async {
    final result = await invokeRpc('list_insurance_providers', {'p_only_active': onlyActive});
    final rawItems = result.data?['providers'] ?? result.data?['items'];
    if (rawItems is! List) {
      return const [];
    }

    return [
      for (final item in rawItems)
        if (item is Map<String, dynamic>)
          InsuranceProvider.fromRow(item)
        else if (item is Map)
          InsuranceProvider.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<InsuranceProvider>().toList(growable: false);
  }

  Future<String> upsertProvider({String? id, required String name, String? contactInfo, bool isActive = true}) async {
    _assertNonEmpty('name', name);

    final result = await invokeRpc('insurance_provider_upsert', {
      if (id != null && id.trim().isNotEmpty) 'p_id': id.trim(),
      'p_name': name.trim(),
      'p_contact_info': contactInfo,
      'p_is_active': isActive,
    });

    final providerId = result.data?['provider_id']?.toString() ?? result.data?.toString();
    if (providerId == null || providerId.isEmpty) {
      throw StateError('Insurance provider upsert returned an unexpected shape.');
    }
    return providerId;
  }

  Future<void> deactivateProvider({required String providerId}) async {
    _assertNonEmpty('providerId', providerId);

    await invokeRpc('insurance_provider_deactivate', {'p_id': providerId.trim()});
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }
}

final insuranceProviderRepositoryProvider = Provider<InsuranceProviderRepository>((ref) {
  return InsuranceProviderRepository(ref.watch(supabaseClientProvider));
});
