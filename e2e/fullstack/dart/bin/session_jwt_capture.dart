import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/supabase_aat_mint_port.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:http/http.dart' as http;

const _defaultSupabaseUrl = 'http://127.0.0.1:54321';
const _defaultAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _defaultPlatformUrl = 'http://127.0.0.1:8787';

/// Records outbound URL and Authorization for E2E-P7.2-08.
class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final authorization = _authorizationHeader(request.headers);
    stdout.writeln(jsonEncode({
      'url': request.url.toString(),
      'authorization': authorization,
    }));
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

  final aatMintPort = SupabaseAatMintPort.withRpc(rpc: rpc.call);
  final billingTokenClient = BillingTokenClient.withRpc(rpc: rpc.call);

  final recordingClient = _RecordingHttpClient(http.Client());
  final discoveryClient = DiscoveryClient(httpClient: recordingClient);
  final usageSummaryClient = UsageSummaryClient(httpClient: recordingClient);
  final submitPort = PlatformHttpsSubmitPort(
    platformBaseUrl: platformUrl,
    httpClient: recordingClient,
  );
  final aboClient = AboClient(
    tokenClient: billingTokenClient,
    httpClient: recordingClient,
  );

  final aat = await aatMintPort.mint();

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
    await aboClient.getOffers();
  } catch (_) {
    // Capture only; billing routes may be empty on a bare stack.
  }
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
