import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';

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

  // Story-specific methods are added in US1–US7 phases.
}

final serviceCatalogRepositoryProvider = Provider<ServiceCatalogRepository>((ref) {
  return ServiceCatalogRepository(ref.watch(supabaseClientProvider));
});
