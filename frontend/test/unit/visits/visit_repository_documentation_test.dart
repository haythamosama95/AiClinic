import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitRepository.saveVisitDocumentation', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: forwards visit id and expected timestamp to save_visit_documentation', () async {
      const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      final expected = DateTime.utc(2026, 5, 31, 10);

      final result = await repository.saveVisitDocumentation(
        visitId: visitId,
        expectedUpdatedAt: expected,
        complaint: 'Chief complaint.',
      );

      expect(client.lastFunction, 'save_visit_documentation');
      expect(client.lastParams?['p_visit_id'], visitId);
      expect(client.lastParams?['p_expected_updated_at'], expected.toUtc().toIso8601String());
      expect(client.lastParams?['p_complaint'], 'Chief complaint.');
      expect(result.visitId, visitId);
    });

    test('advanced: forwards all clinical sections when provided', () async {
      await repository.saveVisitDocumentation(
        visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        complaint: 'Pain',
        history: 'Two days',
        examination: 'Stable',
        diagnosis: 'URI',
        plan: 'Rest',
      );

      expect(client.lastParams?['p_history'], 'Two days');
      expect(client.lastParams?['p_examination'], 'Stable');
      expect(client.lastParams?['p_diagnosis'], 'URI');
      expect(client.lastParams?['p_plan'], 'Rest');
    });

    test('invalid state: STALE_DOCUMENTATION surfaces from RPC', () async {
      client.rpcResults['save_visit_documentation'] = {
        'success': false,
        'error_code': 'STALE_DOCUMENTATION',
        'error_message': 'Stale',
      };

      expect(
        () => repository.saveVisitDocumentation(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'STALE_DOCUMENTATION')),
      );
    });

    test('stupid usage: blank visit id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.saveVisitDocumentation(visitId: '  ', expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10)),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['save_visit_documentation'] = {
        'success': true,
        'data': {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'},
      };

      expect(
        () => repository.saveVisitDocumentation(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: FORBIDDEN when user lacks visits.edit_soap', () async {
      client.rpcResults['save_visit_documentation'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.saveVisitDocumentation(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });
}
