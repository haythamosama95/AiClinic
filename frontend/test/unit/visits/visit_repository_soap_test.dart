import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitRepository.saveSoapNote', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: forwards visit id and expected timestamp to save_soap_note', () async {
      const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      final expected = DateTime.utc(2026, 5, 31, 10);

      final result = await repository.saveSoapNote(
        visitId: visitId,
        expectedUpdatedAt: expected,
        subjective: 'Headache',
      );

      expect(client.lastFunction, 'save_soap_note');
      expect(client.lastParams?['p_visit_id'], visitId);
      expect(client.lastParams?['p_expected_updated_at'], expected.toUtc().toIso8601String());
      expect(client.lastParams?['p_subjective'], 'Headache');
      expect(result.visitId, visitId);
      expect(result.updatedAt, DateTime.parse('2026-05-31T10:05:00.000Z'));
    });

    test('advanced: partial save sends only filled sections', () async {
      await repository.saveSoapNote(
        visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        subjective: 'Note',
        objective: null,
        assessment: null,
        plan: null,
      );

      expect(client.lastParams?['p_subjective'], 'Note');
      expect(client.lastParams?['p_objective'], isNull);
      expect(client.lastParams?['p_assessment'], isNull);
      expect(client.lastParams?['p_plan'], isNull);
    });

    test('advanced: includes specialty JSON when provided', () async {
      const specialty = {'field_a': 'value'};

      await repository.saveSoapNote(
        visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        specialtyFormJson: specialty,
      );

      expect(client.lastParams?['p_specialty_form_json'], specialty);
    });

    test('invalid state: STALE_SOAP surfaces from RPC', () async {
      client.rpcResults['save_soap_note'] = {
        'success': false,
        'error_code': 'STALE_SOAP',
        'error_message': 'Stale',
      };

      expect(
        () => repository.saveSoapNote(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 9),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'STALE_SOAP')),
      );
    });

    test('stupid usage: blank visit id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.saveSoapNote(visitId: '  ', expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10)),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['save_soap_note'] = {
        'success': true,
        'data': {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'},
      };

      expect(
        () => repository.saveSoapNote(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: FORBIDDEN when user lacks visits.edit_soap', () async {
      client.rpcResults['save_soap_note'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.saveSoapNote(
          visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          expectedUpdatedAt: DateTime.utc(2026, 5, 31, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });
}
