import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Clinic-management RPC invoker that provides migration hint and log domain
/// for the V1-2 org/branch management migration.
///
/// Concrete classes must apply both `AppRpcInvoker` and `ClinicManagementRpcInvoker`:
/// ```dart
/// class FooImpl with AppRpcInvoker, ClinicManagementRpcInvoker implements Foo { ... }
/// ```
mixin ClinicManagementRpcInvoker on AppRpcInvoker {
  SupabaseClient get clinicManagementRpcClient;

  @override
  SupabaseClient get rpcClient => clinicManagementRpcClient;

  @override
  String get migrationHint => '20260522100000_org_branch_management.sql';

  @override
  String get rpcLogDomain => 'clinic_management';

  Future<RpcResult> invokeClinicManagementRpc(String functionName, Map<String, dynamic>? params) =>
      invokeRpc(functionName, params);
}
