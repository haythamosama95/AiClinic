import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/core/ai/ai_client_sdk.dart';
import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/supabase_aat_mint_port.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/ai/degraded/ai_degraded_view.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';
import '../../unit/core/ai/fakes.dart';
import 'ai_surface_test_harness.dart';

const _updateCopy = 'Update the app to use AI';

void main() {
  group('E2E-P6.1-05', () {
    testWidgets('E2E-P6.1-05 CONTRACT_VERSION_UNSUPPORTED shows inline update state without dialog', (
      tester,
    ) async {
      final backendRpc = _readPackageVersion('backendRpc');

      final reader = SupabaseAiAvailabilityReader(
        client: _RpcCapturingSupabaseClient(
          onRpc: (functionName, params) async {
            expect(functionName, 'get_ai_status');
            expect(params['p_contract_version'], backendRpc);
            return {
              'success': false,
              'data': {'accepted_versions': [0, 1]},
              'error_code': 'CONTRACT_VERSION_UNSUPPORTED',
              'error_message': 'Contract version is not supported.',
              'contract_version': backendRpc,
            };
          },
        ),
      );

      final mintPort = SupabaseAatMintPort.withRpc(
        rpc: (functionName, params) async {
          expect(functionName, SupabaseAatMintPort.rpcName);
          expect(params['p_contract_version'], backendRpc);
          throw const PostgrestException(
            message: 'CONTRACT_VERSION_UNSUPPORTED',
            code: 'P0001',
          );
        },
      );

      final composition = buildLiveVisitSummaryComposition(
        client: _FakeSupabaseClient(),
        visitId: testVisitId,
        availabilityReader: reader,
        mintPortOverride: mintPort,
        reachabilityPort: FakePlatformReachabilityPort(reachable: true),
        autoInvoke: false,
      );

      await _pumpLiveHost(tester, composition);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.text(_updateCopy), findsOneWidget);
    });
  });

  group('E2E-P6.1-06', () {
    testWidgets(
      'E2E-P6.1-06 discovery and submit send Aip-Contract-Version and mint sends p_contract_version',
      (tester) async {
        final platformClinic = _readPackageVersion('platformClinic');
        final backendRpc = _readPackageVersion('backendRpc');

        final rpcLog = <Map<String, Object?>>[];
        final mintPort = SupabaseAatMintPort.withRpc(
          rpc: (functionName, params) async {
            rpcLog.add({'functionName': functionName, 'params': Map<String, dynamic>.from(params)});
            return 'aat-token-contract-test';
          },
        );

        final httpClient = _ContractVersionHttpClient(
          platformClinic: platformClinic,
          submitEvents: completedStream(requestReference: 'req-contract-06'),
        );

        final discoveryClient = DiscoveryClient(httpClient: httpClient);
        final submitPort = PlatformHttpsSubmitPort(
          platformBaseUrl: testPlatformBaseUrl,
          httpClient: httpClient,
        );

        final reader = SupabaseAiAvailabilityReader(
          client: _RpcCapturingSupabaseClient(
            onRpc: (functionName, params) async {
              expect(functionName, 'get_ai_status');
              expect(params['p_contract_version'], backendRpc);
              return {
                'success': true,
                'contract_version': backendRpc,
                'data': {
                  'available': true,
                  'state': 'active',
                  'reason': 'none',
                  'platform_base_url': testPlatformBaseUrl,
                },
              };
            },
          ),
        );

        final composition = await composeLiveVisitSummaryHost(
          client: _FakeSupabaseClient(),
          visitId: testVisitId,
          availabilityReader: reader,
          reachabilityPort: FakePlatformReachabilityPort(reachable: true),
          mintPortOverride: mintPort,
          submitPortOverride: submitPort,
          discoveryClientOverride: discoveryClient,
          networkSpy: InMemoryPlatformNetworkSpy(),
          contextProviderOverride: HarnessContextProviderPort(),
        );

        final mintCall = rpcLog.singleWhere(
          (entry) => entry['functionName'] == SupabaseAatMintPort.rpcName,
          orElse: () => throw TestFailure('issue_ai_token was not called'),
        );
        expect(mintCall['params'], {'p_contract_version': backendRpc});

        final capabilitiesRequest = httpClient.capabilitiesRequest;
        expect(capabilitiesRequest, isNotNull);
        expect(
          capabilitiesRequest!.headers['aip-contract-version'],
          '$platformClinic',
        );

        final capabilitiesResponse = httpClient.capabilitiesResponse;
        expect(capabilitiesResponse, isNotNull);
        expect(
          capabilitiesResponse!.headers['aip-contract-version'],
          '$platformClinic',
        );
        final body = jsonDecode(capabilitiesResponse.body) as Map<String, dynamic>;
        expect(body['contract_version'], platformClinic);

        await _pumpLiveHost(tester, composition);

        final submitRequest = httpClient.submitRequest;
        expect(submitRequest, isNotNull);
        expect(
          submitRequest!.headers['aip-contract-version'],
          '$platformClinic',
        );
        expect(httpClient.submitHeadersAssignedBeforeBody, isTrue);
      },
    );

    testWidgets('E2E-P6.1-06 contract_version_unsupported shows inline update state without dialog', (
      tester,
    ) async {
      final backendRpc = _readPackageVersion('backendRpc');
      final platformClinic = _readPackageVersion('platformClinic');

      final reader = SupabaseAiAvailabilityReader(
        client: _RpcCapturingSupabaseClient(
          onRpc: (functionName, params) async {
            expect(functionName, 'get_ai_status');
            expect(params['p_contract_version'], backendRpc);
            return {
              'success': true,
              'contract_version': backendRpc,
              'data': {
                'available': true,
                'state': 'active',
                'reason': 'none',
                'platform_base_url': testPlatformBaseUrl,
              },
            };
          },
        ),
      );

      final mintPort = SupabaseAatMintPort.withRpc(
        rpc: (functionName, params) async {
          expect(functionName, SupabaseAatMintPort.rpcName);
          expect(params['p_contract_version'], backendRpc);
          return 'aat-token-contract-test';
        },
      );

      final httpClient = _ContractVersionHttpClient(
        platformClinic: platformClinic,
        capabilitiesStatusCode: 400,
        capabilitiesBody: jsonEncode({
          'code': 'contract_version_unsupported',
          'accepted_versions': [0, 1],
        }),
      );

      final composition = await composeLiveVisitSummaryHost(
        client: _FakeSupabaseClient(),
        visitId: testVisitId,
        availabilityReader: reader,
        reachabilityPort: FakePlatformReachabilityPort(reachable: true),
        mintPortOverride: mintPort,
        discoveryClientOverride: DiscoveryClient(httpClient: httpClient),
        networkSpy: InMemoryPlatformNetworkSpy(),
        contextProviderOverride: HarnessContextProviderPort(),
      );

      await _pumpLiveHost(tester, composition);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(kAiDegradedAppUpdateKey), findsOneWidget);
      expect(find.text(_updateCopy), findsOneWidget);
    });
  });
}

Future<void> _pumpLiveHost(WidgetTester tester, LiveVisitSummaryComposition composition) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: liveVisitSummaryHostBody(visitId: testVisitId, composition: composition),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _readPackageVersion(String key) {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final packagePath = File('$repoRoot/packages/vendor-contracts/src/version.ts');
  final match = RegExp('$key\\s*:\\s*(\\d+)').firstMatch(packagePath.readAsStringSync());
  expect(match, isNotNull, reason: '$key not found in version.ts');
  return int.parse(match!.group(1)!);
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _RpcCapturingSupabaseClient extends Fake implements SupabaseClient {
  _RpcCapturingSupabaseClient({required this.onRpc});

  final dynamic Function(String functionName, Map<String, dynamic> params) onRpc;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    final resolvedParams = params == null ? <String, dynamic>{} : Map<String, dynamic>.from(params);
    return FakePostgrestRpc(onRpc(fn, resolvedParams)) as PostgrestFilterBuilder<T>;
  }
}

class _ContractVersionHttpClient extends http.BaseClient {
  _ContractVersionHttpClient({
    required this.platformClinic,
    this.capabilitiesStatusCode = 200,
    this.capabilitiesBody,
    this.submitEvents,
  });

  final int platformClinic;
  final int capabilitiesStatusCode;
  final String? capabilitiesBody;
  final List<SseEvent>? submitEvents;

  http.BaseRequest? capabilitiesRequest;
  http.Response? capabilitiesResponse;
  http.BaseRequest? submitRequest;
  var submitHeadersAssignedBeforeBody = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/v1/capabilities')) {
      capabilitiesRequest = request;
      final body = capabilitiesBody ??
          jsonEncode({
            'manifests': [sampleActiveManifest()],
            'contract_version': platformClinic,
          });
      capabilitiesResponse = http.Response(
        body,
        capabilitiesStatusCode,
        headers: {
          'content-type': 'application/json',
          if (capabilitiesStatusCode >= 200 && capabilitiesStatusCode < 300)
            'aip-contract-version': '$platformClinic',
        },
      );
      return http.StreamedResponse(
        Stream.value(utf8.encode(capabilitiesResponse!.body)),
        capabilitiesResponse!.statusCode,
        headers: capabilitiesResponse!.headers,
      );
    }

    if (request.url.path.endsWith('/v1/requests')) {
      submitRequest = request;
      final requestBody = request is http.Request ? request.body : '';
      submitHeadersAssignedBeforeBody =
          request.headers.containsKey('aip-contract-version') && requestBody.isNotEmpty;

      final events = submitEvents ?? completedStream(requestReference: 'req-contract-06');
      final payload = _ssePayload(events);
      return http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }

    throw UnsupportedError('Unexpected request: ${request.url}');
  }
}

String _ssePayload(List<SseEvent> events) {
  final buffer = StringBuffer();
  for (final event in events) {
    switch (event) {
      case AcceptedEvent(:final requestReference):
        buffer.writeln('event: accepted');
        buffer.writeln('data: ${jsonEncode({'request_reference': requestReference})}');
        buffer.writeln();
      case CompletedEvent(:final result):
        buffer.writeln('event: completed');
        buffer.writeln('data: ${jsonEncode({'result': result})}');
        buffer.writeln();
      default:
        break;
    }
  }
  return buffer.toString();
}
