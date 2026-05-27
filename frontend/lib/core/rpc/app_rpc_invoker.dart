import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';

/// Shared RPC invocation mixin with log → call → parse → error-map pattern.
///
/// Implementors provide the Supabase client, a log domain prefix, and a
/// migration file hint for missing-function errors.
mixin AppRpcInvoker {
  SupabaseClient get rpcClient;

  /// Optional migration file hint for missing-function or permission errors.
  String? get migrationHint;

  /// Log domain prefix (e.g. `'patients'`, `'settings'`).
  String get rpcLogDomain;

  Future<RpcResult> invokeRpc(String functionName, Map<String, dynamic>? params) async {
    final paramKeys = params?.keys.join(',') ?? 'none';
    AppLog.fine('$rpcLogDomain.rpc.invoke fn=$functionName params=$paramKeys');

    try {
      final dynamic raw;
      if (params == null || params.isEmpty) {
        raw = await rpcClient.rpc(functionName);
      } else {
        raw = await rpcClient.rpc(functionName, params: params);
      }

      final result = RpcResult.fromDynamic(raw);
      if (!result.success) {
        AppLog.warning(
          '$rpcLogDomain.rpc.rejected fn=$functionName code=${result.errorCode} '
          'message=${result.errorMessage}',
        );
        throw RpcFailure(result);
      }

      return result;
    } on AuthException catch (error) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'AUTH_ERROR', errorMessage: error.message));
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
        final hint = migrationHint;
        throw RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'RPC_NOT_APPLIED',
            errorMessage: hint != null
                ? 'Database function "$functionName" is missing. Apply migration: $hint'
                : 'Database function "$functionName" is missing. '
                      'Apply appropriate DB migrations for this service.',
          ),
        );
      }
      if (error.code == '42501' || error.message.contains('permission denied')) {
        final hint = migrationHint;
        throw RpcFailure(
          RpcResult(
            success: false,
            errorCode: 'RPC_NOT_CONFIGURED',
            errorMessage: hint != null
                ? 'Database permissions are incomplete. Apply migration: $hint'
                : 'Database permissions are incomplete. '
                      'Apply appropriate DB grants/migration for this service.',
          ),
        );
      }
      throw RpcFailure(
        RpcResult(success: false, errorCode: error.code ?? 'POSTGREST_ERROR', errorMessage: error.message),
      );
    }
  }
}
