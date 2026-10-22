import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/core/ai/discovery_client.dart';
import 'package:ai_clinic/core/ai/https_submit_port.dart';
import 'package:ai_clinic/core/ai/ports.dart';
import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:ai_clinic/core/contract_version_guard.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _input = CapabilityInvokeInput(
  capabilityId: 'cap',
  capabilityVersion: '1',
  intent: 'intent',
  context: {},
);

Map<String, Object?> _tokenReply({int? version}) => {
      'success': true,
      if (version != null) 'contract_version': version,
      'data': {
        'token': 'token-r2c3',
        'abo_base_url': 'https://abo.example',
        'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      },
    };

http.StreamedResponse _sse(String body, {String? version}) => http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {
        'content-type': 'text/event-stream',
        if (version != null) 'aip-contract-version': version,
      },
    );

void main() {
  group('R2-C3 RpcResult version retention', () {
    test('R2-C3: rpc_result map and positional forms retain the echoed version', () {
      expect(
        RpcResult.fromDynamic({'success': true, 'data': {}, 'contract_version': 1}).contractVersion,
        1,
      );
      expect(RpcResult.fromDynamic([true, null, null, null, 1]).contractVersion, 1);
      expect(RpcResult.fromDynamic([true, null, null, null]).contractVersion, isNull);
    });
  });

  group('R2-C3 version guard', () {
    test('R2-C3: previous and current known versions are accepted, unknown sent is rejected', () {
      expect(isKnownContractVersion(1, current: 1), isTrue);
      expect(isKnownContractVersion(0, current: 1), isTrue);
      expect(isKnownContractVersion(2, current: 1), isFalse);
      expect(isKnownContractVersion(-1, current: 0), isFalse);
    });

    test('R2-C3: header echo must match the sent version, body echo only when present', () {
      expect(
        echoesContractVersion(
          headers: {'Aip-Contract-Version': '1'},
          headerName: 'aip-contract-version',
          sent: 1,
          current: 1,
        ),
        isTrue,
      );
      expect(
        echoesContractVersion(
          headers: {'aip-contract-version': '1'},
          headerName: 'aip-contract-version',
          sent: 1,
          current: 1,
          body: {'contract_version': 0},
        ),
        isFalse,
      );
      expect(
        echoesContractVersion(
          headers: {'aip-contract-version': '1'},
          headerName: 'aip-contract-version',
          sent: 1,
          current: 1,
          body: const {},
          bodyRequired: true,
        ),
        isFalse,
      );
    });
  });

  group('R2-C3 RPC adapters', () {
    test('R2-C3: supported echoed billing token reply mints a session', () async {
      final client = BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply(version: 1));
      final session = await client.ensureToken();
      expect(session.token, 'token-r2c3');
      client.dispose();
    });

    test('R2-C3: unversioned billing token reply is rejected before any session is stored', () async {
      final client = BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply());
      await expectLater(
        client.ensureToken(),
        throwsA(isA<ContractVersionUnsupportedException>()),
      );
      client.dispose();
    });

    test('R2-C3: mismatched availability reply is rejected before status is read', () async {
      final reader = SupabaseAiAvailabilityReader.withRpc(
        rpc: (_, __) async => {'success': true, 'data': null, 'contract_version': 0},
      );
      await expectLater(reader.read(), throwsA(isA<ContractVersionUnsupportedException>()));
    });

    test('R2-C3: supported availability reply with echoed current version is read', () async {
      final reader = SupabaseAiAvailabilityReader.withRpc(
        rpc: (_, __) async => {'success': true, 'data': null, 'contract_version': backendRpc},
      );
      expect(await reader.read(), AiAvailability.nonEnrolled);
    });
  });

  group('R2-C3 ABO adapter', () {
    test('R2-C3: supported ABO header and body echo decodes the subscription', () async {
      final tokenClient = BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply(version: 1));
      final client = AboClient(
        tokenClient: tokenClient,
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'contract_version': 1,
                'subscription_ref': 'AIC-R2C3',
                'snapshot': null,
                'notices': <Object>[],
              }),
              200,
              headers: {'abo-contract-version': '1'},
            )),
      );
      final response = await client.getSubscription();
      expect(response.subscriptionRef, 'AIC-R2C3');
      tokenClient.dispose();
    });

    test('R2-C3: ABO success reply without the version header is rejected before DTO construction', () async {
      final tokenClient = BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply(version: 1));
      final client = AboClient(
        tokenClient: tokenClient,
        httpClient: MockClient((_) async => http.Response(
              // Malformed notices would fail DTO construction if it were reached.
              jsonEncode({'contract_version': 1, 'subscription_ref': 'x', 'notices': 'bad'}),
              200,
            )),
      );
      await expectLater(
        client.getSubscription(),
        throwsA(isA<AboContractVersionUnsupportedException>()),
      );
      tokenClient.dispose();
    });
  });

  group('R2-C3 platform clients', () {
    test('R2-C3: supported discovery reply with echoed version returns manifests', () async {
      final client = DiscoveryClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'manifests': <Object>[], 'contract_version': platformClinic}),
              200,
              headers: {'aip-contract-version': '$platformClinic'},
            )),
      );
      final result = await client.fetchCapabilities(platformBaseUrl: 'https://platform.test', aat: 'aat');
      expect(result.manifests, isEmpty);
      expect(result.notModified, isFalse);
    });

    test('R2-C3: unknown contract version reply is rejected before DTO construction', () async {
      final client = DiscoveryClient(
        httpClient: MockClient((_) async => http.Response(
              // Non-object manifest entries would throw a TypeError if DTOs were built.
              jsonEncode({'manifests': ['not-an-object'], 'contract_version': 99}),
              200,
              headers: {'aip-contract-version': '99'},
            )),
      );
      await expectLater(
        client.fetchCapabilities(platformBaseUrl: 'https://platform.test', aat: 'aat'),
        throwsA(isA<ContractVersionUnsupportedException>()),
      );
    });

    test('R2-C3: supported usage reply with echoed version reads the term', () async {
      final result = await UsageSummaryClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'contract_version': 1,
                'subscription_ref': 'sub-r2c3',
                'snapshot': {
                  'term': {'used': 3, 'allowance': 10, 'plan_display_name': 'Plan'},
                },
              }),
              200,
              headers: {'aip-contract-version': '1'},
            )),
      ).fetchUsage(platformBaseUrl: 'https://platform.test', aat: 'aat');
      expect(result.creditsUsed, 3);
    });

    test('R2-C3: usage reply missing the version header is rejected before coverage fields are read', () async {
      final client = UsageSummaryClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'subscription_ref': 'sub-r2c3', 'snapshot': {'term': null}}),
              200,
            )),
      );
      await expectLater(
        client.fetchUsage(platformBaseUrl: 'https://platform.test', aat: 'aat'),
        throwsA(isA<ContractVersionUnsupportedException>()),
      );
    });

    test('R2-C3: supported submit stream with echoed version opens a connection', () async {
      final port = PlatformHttpsSubmitPort(
        platformBaseUrl: 'https://platform.test',
        httpClient: _FixedStreamClient(_sse('', version: '$platformClinic')),
      );
      final connection = await port.submit(
        input: _input,
        headers: const SubmitRequestHeaders(
          aat: 'aat',
          idempotencyKey: 'key',
          traceId: 'trace',
          capabilityVersion: '1',
        ),
      );
      connection.close();
    });

    test('R2-C3: submit stream with an unknown version is closed unread and rejected', () async {
      final body = StreamController<List<int>>();
      var cancelled = false;
      body.onCancel = () => cancelled = true;
      final port = PlatformHttpsSubmitPort(
        platformBaseUrl: 'https://platform.test',
        httpClient: _FixedStreamClient(
          http.StreamedResponse(body.stream, 200, headers: {
            'content-type': 'text/event-stream',
            'aip-contract-version': '99',
          }),
        ),
      );
      await expectLater(
        port.submit(
          input: _input,
          headers: const SubmitRequestHeaders(
            aat: 'aat',
            idempotencyKey: 'key',
            traceId: 'trace',
            capabilityVersion: '1',
          ),
        ),
        throwsA(isA<ContractVersionUnsupportedException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await body.close();
    });
  });
}

class _FixedStreamClient extends http.BaseClient {
  _FixedStreamClient(this._response);

  final http.StreamedResponse _response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => _response;
}
