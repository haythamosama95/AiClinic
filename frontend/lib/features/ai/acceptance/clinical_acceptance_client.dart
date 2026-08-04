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
    final raw = await _client.rpc(
      'record_ai_acceptance',
      params: {
        'p_request_reference': requestReference,
        'p_target_key': targetKey,
        'p_target_args': targetArgs,
      },
    );
    return RpcResult.fromDynamic(raw);
  }
}
