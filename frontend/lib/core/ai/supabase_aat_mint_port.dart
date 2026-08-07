import 'package:supabase_flutter/supabase_flutter.dart';

import 'ports.dart';

/// Injectable RPC callable for unit tests.
typedef AatMintRpcInvoke = Future<dynamic> Function(String functionName, Map<String, dynamic> params);

/// Production [AatMintPort] over clinic `public.issue_ai_token` (Band B).
///
/// Does not reinterpret E2 mint/cache/remint rules — the SDK owns caching.
class SupabaseAatMintPort implements AatMintPort {
  SupabaseAatMintPort({required SupabaseClient client})
      : this.withRpc(
          rpc: (functionName, params) => client.rpc(functionName, params: params),
        );

  /// Test / injectable seam.
  SupabaseAatMintPort.withRpc({required AatMintRpcInvoke rpc}) : _rpc = rpc;

  final AatMintRpcInvoke _rpc;

  static const rpcName = 'issue_ai_token';

  @override
  Future<String> mint() async {
    final raw = await _rpc(rpcName, const {});
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    throw StateError('issue_ai_token returned an empty token');
  }
}
