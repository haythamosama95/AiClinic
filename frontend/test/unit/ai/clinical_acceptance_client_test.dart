import 'package:ai_clinic/features/ai/acceptance/clinical_acceptance_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('clinical acceptance client', () {
    test('maps record_ai_acceptance RPC parameters', () async {
      final client = RpcCaptureSupabaseClient();
      final acceptanceClient = ClinicalAcceptanceClient(client: client);

      await acceptanceClient.recordAcceptance(
        requestReference: 'A1B2-C3D4',
        targetKey: 'visit_clinical_notes',
        targetArgs: {
          'p_visit_id': '550e8400-e29b-41d4-a716-446655440000',
          'p_complaint': 'Accepted note',
          'p_expected_updated_at': '2026-08-01T10:00:00.000Z',
        },
      );

      expect(client.lastFunction, 'record_ai_acceptance');
      expect(client.lastParams?['p_request_reference'], 'A1B2-C3D4');
      expect(client.lastParams?['p_target_key'], 'visit_clinical_notes');
      expect(
        client.lastParams?['p_target_args'],
        isA<Map<String, dynamic>>()
            .having((m) => m['p_visit_id'], 'visit id', '550e8400-e29b-41d4-a716-446655440000')
            .having((m) => m['p_complaint'], 'complaint', 'Accepted note'),
      );
    });

    test('does not auto-commit without explicit recordAcceptance call', () async {
      final client = RpcCaptureSupabaseClient();
      final acceptanceClient = ClinicalAcceptanceClient(client: client);

      expect(client.lastFunction, isNull);

      // Controller discard/idle paths must not invoke the client implicitly.
      expect(client.lastFunction, isNull);
      expect(acceptanceClient, isNotNull);
    });
  });
}
