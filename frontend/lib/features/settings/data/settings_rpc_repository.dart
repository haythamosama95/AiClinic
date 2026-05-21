import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Maps settings admin RPC PostgREST failures to [RpcFailure], or returns null to rethrow.
RpcFailure? settingsRpcFailureFromPostgrest(PostgrestException error, String functionName) {
  if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
    return RpcFailure(
      RpcResult(
        success: false,
        errorCode: 'RPC_NOT_APPLIED',
        errorMessage:
            'Database function "$functionName" is missing. Apply backend migrations '
            '(20260522100000_org_branch_management.sql) and restart Supabase.',
      ),
    );
  }
  return null;
}

/// Shared RPC invoke helper for V1-2 settings repositories.
mixin SettingsRpcInvoker {
  SupabaseClient get settingsRpcClient;

  Future<RpcResult> invokeSettingsRpc(String functionName, Map<String, dynamic>? params) async {
    AppLog.fine('settings.rpc.invoke fn=$functionName params=${params?.keys.join(',') ?? 'none'}');

    try {
      final dynamic raw;
      if (params == null || params.isEmpty) {
        raw = await settingsRpcClient.rpc(functionName);
      } else {
        raw = await settingsRpcClient.rpc(functionName, params: params);
      }

      final result = RpcResult.fromDynamic(raw);
      if (!result.success) {
        AppLog.warning(
          'settings.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
        throw RpcFailure(result);
      }

      return result;
    } on PostgrestException catch (error) {
      final mapped = settingsRpcFailureFromPostgrest(error, functionName);
      if (mapped != null) {
        throw mapped;
      }
      rethrow;
    }
  }
}
