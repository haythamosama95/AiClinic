import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'context_provider_port.dart';

/// Injectable RPC callable for [SupabaseContextProviderPort] unit tests.
typedef ContextProviderRpcInvoke = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Production [ContextProviderPort] over `public.get_visit_chief_complaint`.
///
/// Visit id is constructor-injected (per-visit port construction). The Resolver
/// key-list API stays argument-free; hosts build one port per screen/visit.
class SupabaseContextProviderPort implements ContextProviderPort {
  SupabaseContextProviderPort({
    required SupabaseClient client,
    required String visitId,
  }) : this.withRpc(
          rpc: (functionName, params) async =>
              await client.rpc(functionName, params: params),
          visitId: visitId,
        );

  /// Test / injectable seam — prefer [SupabaseContextProviderPort] in production.
  SupabaseContextProviderPort.withRpc({
    required ContextProviderRpcInvoke rpc,
    required String visitId,
  })  : _rpc = rpc,
        _visitId = visitId;

  final ContextProviderRpcInvoke _rpc;
  final String _visitId;

  static const rpcName = 'get_visit_chief_complaint';

  @override
  Future<Map<String, Object?>> fetchVisitChiefComplaint() async {
    final raw = await _rpc(rpcName, {'p_visit_id': _visitId});
    final result = RpcResult.fromDynamic(raw);
    if (!result.success) {
      throw RpcFailure(result);
    }
    final data = result.data;
    if (data == null) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'EMPTY_DATA',
          errorMessage: 'get_visit_chief_complaint returned no data',
        ),
      );
    }
    return <String, Object?>{
      for (final entry in data.entries) entry.key: entry.value,
    };
  }
}
