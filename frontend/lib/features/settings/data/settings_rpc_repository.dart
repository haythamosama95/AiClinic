import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Settings-specific RPC invoker that provides migration hint and log domain
/// for the V1-2 settings migration.
///
/// Concrete classes must apply both `AppRpcInvoker` and `SettingsRpcInvoker`:
/// ```dart
/// class FooImpl with AppRpcInvoker, SettingsRpcInvoker implements Foo { ... }
/// ```
mixin SettingsRpcInvoker on AppRpcInvoker {
  SupabaseClient get settingsRpcClient;

  @override
  SupabaseClient get rpcClient => settingsRpcClient;

  @override
  String get migrationHint => '20260522100000_org_branch_management.sql';

  @override
  String get rpcLogDomain => 'settings';

  Future<RpcResult> invokeSettingsRpc(String functionName, Map<String, dynamic>? params) =>
      invokeRpc(functionName, params);
}
