import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'clinical_acceptance_port.dart';

/// Production Supabase RPC caller for [public.record_ai_acceptance].
class ClinicalAcceptanceClient implements ClinicalAcceptancePort {
  ClinicalAcceptanceClient({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<RpcResult> recordAcceptance({
    required String requestReference,
    required String targetKey,
    required Map<String, dynamic> targetArgs,
  }) async {
    try {
      final raw = await _client.rpc(
        'record_ai_acceptance',
        params: {
          'p_request_reference': requestReference,
          'p_target_key': targetKey,
          'p_target_args': targetArgs,
        },
      );
      return RpcResult.fromDynamic(raw);
    } on AuthException catch (error) {
      return RpcResult(success: false, errorCode: 'AUTH_ERROR', errorMessage: error.message);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.message.contains('Could not find the function')) {
        return const RpcResult(
          success: false,
          errorCode: 'RPC_NOT_APPLIED',
          errorMessage:
              'Database function "record_ai_acceptance" is missing. '
              'Apply appropriate DB migrations for this service.',
        );
      }
      if (error.code == '42501' || error.message.contains('permission denied')) {
        return const RpcResult(
          success: false,
          errorCode: 'RPC_NOT_CONFIGURED',
          errorMessage:
              'Database permissions are incomplete. '
              'Apply appropriate DB grants/migration for this service.',
        );
      }
      return RpcResult(
        success: false,
        errorCode: error.code ?? 'POSTGREST_ERROR',
        errorMessage: error.message,
      );
    }
  }
}
