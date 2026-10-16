import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_availability.dart';

/// Injectable RPC callable for unit tests.
typedef AiAvailabilityRpcInvoke = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Production reader for `public.get_ai_status(p_contract_version)` — never probes
/// the platform to discover enrollment (FR-009).
class SupabaseAiAvailabilityReader implements AiAvailabilityReader {
  SupabaseAiAvailabilityReader({SupabaseClient? client})
      : this.withRpc(
          rpc: (functionName, params) async =>
              (client ?? Supabase.instance.client).rpc(functionName, params: params),
        );

  /// Test / injectable seam.
  SupabaseAiAvailabilityReader.withRpc({required AiAvailabilityRpcInvoke rpc}) : _rpc = rpc;

  final AiAvailabilityRpcInvoke _rpc;

  static const rpcName = 'get_ai_status';

  @override
  Future<AiAvailability> read() async {
    final raw = await _rpc(rpcName, {'p_contract_version': backendRpc});
    final result = RpcResult.fromDynamic(raw);

    if (!result.success) {
      if (result.errorCode == 'CONTRACT_VERSION_UNSUPPORTED') {
        throw const ContractVersionUnsupportedException();
      }
      throw RpcFailure(result);
    }

    final data = result.data;
    if (data == null) {
      return AiAvailability.nonEnrolled;
    }

    return AiAvailability.fromJson(data);
  }
}

/// HTTP reachability check for enrolled installations (A1 `/health`).
class HttpPlatformReachabilityPort implements PlatformReachabilityPort {
  HttpPlatformReachabilityPort({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<bool> isReachable(String platformBaseUrl) async {
    final base = platformBaseUrl.endsWith('/')
        ? platformBaseUrl.substring(0, platformBaseUrl.length - 1)
        : platformBaseUrl;
    try {
      final response = await _client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
