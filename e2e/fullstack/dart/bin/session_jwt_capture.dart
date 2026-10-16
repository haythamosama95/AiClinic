import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:http/http.dart' as http;

const _defaultSupabaseUrl = 'http://127.0.0.1:54321';
const _defaultAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _defaultPlatformUrl = 'http://127.0.0.1:8787';
const _defaultAboUrl = 'http://127.0.0.1:8788';

/// Records outbound URL and Authorization for E2E-P7.2-08.
class _RecordingHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String _platformUrl;
  final String _aboUrl;

  _RecordingHttpClient(
    this._inner, {
    required String platformUrl,
    required String aboUrl,
  })  : _platformUrl = platformUrl,
        _aboUrl = aboUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authorization = _authorizationHeader(request.headers);
    final url = request.url.toString();
    final service = url.startsWith(_platformUrl)
        ? 'platform'
        : url.startsWith(_aboUrl)
            ? 'abo'
            : null;
    if (service != null) {
      stdout.writeln(jsonEncode({
        'service': service,
        'url': url,
        'authorization': authorization,
      }));
    }
    return _inner.send(request);
  }

  String? _authorizationHeader(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        return entry.value;
      }
    }
    return null;
  }
}

Future<void> main() async {
  final supabaseUrl = Platform.environment['SUPABASE_URL'] ?? _defaultSupabaseUrl;
  final anonKey =
      Platform.environment['SUPABASE_ANON_KEY'] ?? Platform.environment['ANON_KEY'] ?? _defaultAnonKey;
  final platformUrl = Platform.environment['PLATFORM_URL'] ?? _defaultPlatformUrl;
  final aboUrl = Platform.environment['ABO_URL'] ?? _defaultAboUrl;
  final email = Platform.environment['P7_2_SESSION_EMAIL'] ?? 'admin';
  final password = Platform.environment['P7_2_SESSION_PASSWORD'] ?? 'admin';

  final sessionJwt = await _signIn(
    supabaseUrl: supabaseUrl,
    anonKey: anonKey,
    email: email,
    password: password,
  );

  final rpc = _SupabaseRpcClient(
    supabaseUrl: supabaseUrl,
    anonKey: anonKey,
    sessionJwt: sessionJwt,
  );

  stdout.writeln(jsonEncode({'session_jwt': sessionJwt}));

  final recordingClient = _RecordingHttpClient(
    http.Client(),
    platformUrl: platformUrl,
    aboUrl: aboUrl,
  );
  final discoveryClient = DiscoveryClient(httpClient: recordingClient);
  final usageSummaryClient = UsageSummaryClient(httpClient: recordingClient);
  final submitPort = PlatformHttpsSubmitPort(
    platformBaseUrl: platformUrl,
    httpClient: recordingClient,
  );
  final aat = await rpc.call('issue_ai_token', {'p_contract_version': backendRpc});
  if (aat is! String || aat.isEmpty) {
    throw StateError('issue_ai_token returned an empty token');
  }

  try {
    await discoveryClient.fetchCapabilities(platformBaseUrl: platformUrl, aat: aat);
  } catch (_) {
    // Capture only; platform may deny without a full H-FS fixture.
  }

  try {
    await usageSummaryClient.fetchUsage(platformBaseUrl: platformUrl, aat: aat);
  } catch (_) {
    // Capture only; coverage may be absent on a bare stack.
  }

  try {
    final connection = await submitPort.submit(
      input: CapabilityInvokeInput(
        capabilityId: 'clinic.visit_summary',
        capabilityVersion: '1',
        intent: 'p7-2 credential isolation probe',
        context: {},
      ),
      headers: SubmitRequestHeaders(
        idempotencyKey: 'p7-2-session-jwt-capture',
        traceId: 'p7-2-session-jwt-capture',
        capabilityVersion: '1',
        aat: aat,
      ),
    );
    connection.close();
  } catch (_) {
    // Capture only; pre-stream denial still records Authorization.
  }

  try {
    final billingRaw = await rpc.call(
      'issue_billing_token',
      {'p_contract_version': backendRpc},
    );
    final billing = _readRpcResult(billingRaw);
    final billingData = billing['data'];
    if (!_isSuccess(billing['success']) || billingData is! Map) {
      throw StateError('issue_billing_token returned an invalid result');
    }
    final billingSession = Map<String, dynamic>.from(billingData);
    final billingToken = billingSession['token']?.toString();
    final aboBaseUrl = billingSession['abo_base_url']?.toString();
    if (billingToken == null || billingToken.isEmpty || aboBaseUrl == null || aboBaseUrl.isEmpty) {
      throw StateError('issue_billing_token returned an incomplete session');
    }
    final normalizedAboUrl = aboBaseUrl.endsWith('/')
        ? aboBaseUrl.substring(0, aboBaseUrl.length - 1)
        : aboBaseUrl;
    await recordingClient.get(
      Uri.parse('$normalizedAboUrl/v1/offers'),
      headers: {
        'authorization': 'Bearer $billingToken',
        'accept': 'application/json',
        'abo-contract-version': '$aboClinic',
        'host': Uri.parse(aboBaseUrl).host == '127.0.0.1' ||
                Uri.parse(aboBaseUrl).host == 'localhost'
            ? 'billing.vendor.test'
            : Uri.parse(aboBaseUrl).host,
      },
    );
  } catch (_) {
    // Capture only; billing routes may be empty on a bare stack.
  }
}

Map<String, dynamic> _readRpcResult(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List && raw.length >= 4) {
    return {
      'success': raw[0],
      'data': raw[1],
      'error_code': raw[2],
      'error_message': raw[3],
    };
  }
  throw FormatException('Unrecognized RPC result: $raw');
}

bool _isSuccess(Object? value) {
  final normalized = value?.toString().toLowerCase();
  return value == true || normalized == 't' || normalized == 'true';
}

Future<String> _signIn({
  required String supabaseUrl,
  required String anonKey,
  required String email,
  required String password,
}) async {
  final base = supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl;
  final response = await http.post(
    Uri.parse('$base/auth/v1/token?grant_type=password'),
    headers: {
      'apikey': anonKey,
      'content-type': 'application/json',
    },
    body: jsonEncode({'email': email, 'password': password}),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    stderr.writeln('sign-in failed (${response.statusCode}): ${response.body}');
    exit(1);
  }
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) {
    stderr.writeln('sign-in response is not an object');
    exit(1);
  }
  final accessToken = decoded['access_token']?.toString();
  if (accessToken == null || accessToken.isEmpty) {
    stderr.writeln('sign-in response missing access_token');
    exit(1);
  }
  return accessToken;
}

class _SupabaseRpcClient {
  _SupabaseRpcClient({
    required this.supabaseUrl,
    required this.anonKey,
    required this.sessionJwt,
  });

  final String supabaseUrl;
  final String anonKey;
  final String sessionJwt;

  Future<dynamic> call(String functionName, Map<String, dynamic> params) async {
    final base = supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl;
    final response = await http.post(
      Uri.parse('$base/rest/v1/rpc/$functionName'),
      headers: {
        'apikey': anonKey,
        'authorization': 'Bearer $sessionJwt',
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(params),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('$functionName failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body);
  }
}
