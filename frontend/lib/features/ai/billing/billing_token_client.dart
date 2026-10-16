import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Injectable RPC callable for unit tests.
typedef BillingTokenRpcInvoke = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// In-memory billing token minted by `issue_billing_token`.
class BillingTokenSession {
  const BillingTokenSession({
    required this.token,
    required this.aboBaseUrl,
    required this.expiresAt,
  });

  final String token;
  final String aboBaseUrl;
  final DateTime expiresAt;
}

/// Mints and renews billing tokens for one billing page session.
///
/// Tokens stay in memory only for the lifetime of this client instance.
class BillingTokenClient {
  BillingTokenClient({SupabaseClient? client})
      : this.withRpc(
          rpc: (functionName, params) async =>
              (client ?? Supabase.instance.client).rpc(functionName, params: params),
        );

  /// Test / injectable seam.
  BillingTokenClient.withRpc({required BillingTokenRpcInvoke rpc}) : _rpc = rpc;

  static const rpcName = 'issue_billing_token';
  static const _renewBeforeExpiry = Duration(seconds: 30);

  final BillingTokenRpcInvoke _rpc;
  BillingTokenSession? _session;
  Future<BillingTokenSession>? _mintInFlight;

  /// Returns a valid billing token, minting on first use and renewing before expiry.
  Future<BillingTokenSession> ensureToken() {
    final current = _session;
    if (current != null && !_needsRenewal(current)) {
      return Future.value(current);
    }
    return _mint();
  }

  /// Clears the in-memory session.
  void dispose() {
    _session = null;
    _mintInFlight = null;
  }

  bool _needsRenewal(BillingTokenSession session) {
    return DateTime.now().isAfter(session.expiresAt.subtract(_renewBeforeExpiry));
  }

  Future<BillingTokenSession> _mint() {
    final inFlight = _mintInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _callMint();
    _mintInFlight = future;
    return future;
  }

  Future<BillingTokenSession> _callMint() async {
    try {
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
        throw StateError('issue_billing_token returned no data');
      }

      final token = data['token']?.toString();
      final aboBaseUrl = data['abo_base_url']?.toString();
      final expiresAtRaw = data['expires_at'];
      if (token == null || token.isEmpty || aboBaseUrl == null || aboBaseUrl.isEmpty) {
        throw StateError('issue_billing_token returned an incomplete session');
      }

      final expiresAt = _parseExpiresAt(expiresAtRaw);
      final session = BillingTokenSession(
        token: token,
        aboBaseUrl: aboBaseUrl,
        expiresAt: expiresAt,
      );
      _session = session;
      return session;
    } on PostgrestException catch (error) {
      if (error.message.contains('CONTRACT_VERSION_UNSUPPORTED')) {
        throw const ContractVersionUnsupportedException();
      }
      rethrow;
    } finally {
      _mintInFlight = null;
    }
  }

  DateTime _parseExpiresAt(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    throw FormatException('issue_billing_token expires_at is invalid: $raw');
  }
}
