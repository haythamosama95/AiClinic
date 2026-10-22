import 'dart:convert';

import 'package:ai_clinic/core/ai/usage_summary_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

UsageSummaryClient _clientReturning(Map<String, Object?> body) => UsageSummaryClient(
  httpClient: MockClient(
    (request) async => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json', 'aip-contract-version': '1'},
    ),
  ),
);

void main() {
  group('R7-T2 usage summary snapshot decoding', () {
    test('R7-T2: active coverage response renders gauge and plan reference', () async {
      final result = await _clientReturning({
        'subscription_ref': 'sub-fixture-001',
        'snapshot': {
          'term': {'used': 42, 'allowance': 10000, 'plan_display_name': 'Fixture Plan'},
        },
        'queued_terms': <Object>[],
        'recent_terms': <Object>[],
      }).fetchUsage(platformBaseUrl: 'https://platform.test', aat: 'aat');

      expect(result.creditsUsed, 42);
      expect(result.creditBudget, 10000);
      expect(result.planDisplayName, 'Fixture Plan');
      expect(result.subscriptionRef, 'sub-fixture-001');
    });

    test('R7-T2: valid no-term snapshot keeps reference and hides gauge', () async {
      final result = await _clientReturning({
        'subscription_ref': 'sub-fixture-001',
        'snapshot': {'term': null},
        'queued_terms': <Object>[],
        'recent_terms': <Object>[],
      }).fetchUsage(platformBaseUrl: 'https://platform.test', aat: 'aat');

      expect(result.creditsUsed, isNull);
      expect(result.creditBudget, isNull);
      expect(result.planDisplayName, isNull);
      expect(result.subscriptionRef, 'sub-fixture-001');
    });

    test('R7-T2: absent snapshot is malformed and shows no fabricated zeros', () async {
      final client = _clientReturning({
        'subscription_ref': 'sub-fixture-001',
        'queued_terms': <Object>[],
        'recent_terms': <Object>[],
      });

      await expectLater(
        client.fetchUsage(platformBaseUrl: 'https://platform.test', aat: 'aat'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
