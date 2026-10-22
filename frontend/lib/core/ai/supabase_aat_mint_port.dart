import 'dart:convert';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
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

  /// Expected `ver` claim in the AI token JWS payload (backend mint sets `'ver', '2'`).
  static const expectedTokenVer = '2';

  @override
  Future<String> mint() async {
    try {
      final raw = await _rpc(rpcName, {'p_contract_version': backendRpc});
      if (raw is String && raw.isNotEmpty) {
        if (_jwsPayloadVer(raw) != expectedTokenVer) {
          throw const ContractVersionUnsupportedException();
        }
        return raw;
      }
      throw StateError('issue_ai_token returned an empty token');
    } on PostgrestException catch (error) {
      if (error.message.contains('CONTRACT_VERSION_UNSUPPORTED')) {
        throw const ContractVersionUnsupportedException();
      }
      rethrow;
    }
  }
}

/// Returns the `ver` claim of a three-segment JWS token, or null when the token
/// is malformed, its payload is not base64url JSON, or `ver` is absent or not a string.
String? _jwsPayloadVer(String token) {
  final segments = token.split('.');
  if (segments.length != 3) {
    return null;
  }
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))));
    if (payload is! Map) {
      return null;
    }
    final ver = payload['ver'];
    return ver is String ? ver : null;
  } on FormatException {
    return null;
  }
}
