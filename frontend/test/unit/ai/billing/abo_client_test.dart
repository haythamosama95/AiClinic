import 'dart:convert';

import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('R3-C2 AboClient', () {
    test('maps idempotency_conflict to its typed clinic error', () async {
      final tokenClient = BillingTokenClient.withRpc(
        rpc: (_, __) async => {
          'success': true,
          'data': {
            'token': 'test-token',
            'abo_base_url': 'https://abo.example',
            'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
          },
        },
      );
      final client = AboClient(
        tokenClient: tokenClient,
        httpClient: MockClient((_) async => http.Response(
          jsonEncode({'code': 'idempotency_conflict', 'contract_version': 1}),
          409,
        )),
      );

      await expectLater(
        client.putBillingContact(
          clientRequestId: 'same-key',
          name: 'Clinic',
          email: 'clinic@example.test',
          phone: '+201000000000',
        ),
        throwsA(isA<AboIdempotencyConflictException>()),
      );
      tokenClient.dispose();
    });
  });
}
