import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitRepository.completeVisit', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: forwards visit id and optional expected timestamp', () async {
      const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
      final expected = DateTime.utc(2026, 5, 31, 10);

      final result = await repository.completeVisit(visitId: visitId, expectedUpdatedAt: expected);

      expect(client.lastFunction, 'complete_visit');
      expect(client.lastParams?['p_visit_id'], visitId);
      expect(client.lastParams?['p_expected_updated_at'], expected.toUtc().toIso8601String());
      expect(result.visitId, visitId);
      expect(result.visitStatus, 'completed');
      expect(result.appointmentStatus, 'completed');
    });

    test('advanced: omits expected timestamp when not provided', () async {
      await repository.completeVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');

      expect(client.lastParams?.containsKey('p_expected_updated_at'), isFalse);
    });

    test('invalid state: SOAP_REQUIRED_FOR_COMPLETE surfaces from RPC', () async {
      client.rpcResults['complete_visit'] = {
        'success': false,
        'error_code': 'SOAP_REQUIRED_FOR_COMPLETE',
        'error_message': 'SOAP required',
      };

      expect(
        () => repository.completeVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'SOAP_REQUIRED_FOR_COMPLETE')),
      );
    });

    test('stupid usage: blank visit id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.completeVisit(visitId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['complete_visit'] = {
        'success': true,
        'data': {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'},
      };

      expect(
        () => repository.completeVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: APPOINTMENT_NOT_IN_PROGRESS when appointment already completed', () async {
      client.rpcResults['complete_visit'] = {
        'success': false,
        'error_code': 'APPOINTMENT_NOT_IN_PROGRESS',
        'error_message': 'Not in progress',
      };

      expect(
        () => repository.completeVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'APPOINTMENT_NOT_IN_PROGRESS')),
      );
    });
  });

  group('VisitRepository.listPatientVisits', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: forwards patient id with default pagination', () async {
      const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

      final page = await repository.listPatientVisits(patientId: patientId);

      expect(client.lastFunction, 'list_patient_visits');
      expect(client.lastParams?['p_patient_id'], patientId);
      expect(client.lastParams?['p_limit'], 50);
      expect(client.lastParams?['p_offset'], 0);
      expect(page.items, hasLength(1));
      expect(page.items.first.doctorName, 'Dr Test');
      expect(page.items.first.status, VisitStatus.completed);
      expect(page.totalCount, 1);
    });

    test('advanced: custom limit and offset forwarded', () async {
      await repository.listPatientVisits(patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', limit: 10, offset: 20);

      expect(client.lastParams?['p_limit'], 10);
      expect(client.lastParams?['p_offset'], 20);
    });

    test('invalid state: blank patient id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.listPatientVisits(patientId: ''),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('edge case: malformed payload throws StateError', () async {
      client.rpcResults['list_patient_visits'] = {'success': true, 'data': null};

      expect(
        () => repository.listPatientVisits(patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: FORBIDDEN without patients.view', () async {
      client.rpcResults['list_patient_visits'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.listPatientVisits(patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.getVisit permission subsets', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: clinical payload includes SOAP sections', () async {
      client.rpcResults['get_visit'] = {
        'success': true,
        'data': {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'completed',
          'soap': {
            'subjective': 'Chief complaint.',
            'objective': 'Exam findings.',
            'assessment': null,
            'plan': null,
            'specialty_form_json': {},
            'updated_at': '2026-05-31T10:00:00.000Z',
          },
        },
      };

      final detail = await repository.getVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');

      expect(detail.soap?.subjective, 'Chief complaint.');
      expect(detail.soap?.hasAnySection, isTrue);
    });

    test('advanced: metadata-only payload omits SOAP', () async {
      client.rpcResults['get_visit'] = {
        'success': true,
        'data': {
          'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'completed',
        },
      };

      final detail = await repository.getVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');

      expect(detail.soap, isNull);
      expect(detail.status, VisitStatus.completed);
    });

    test('edge case: empty visit id rejected before RPC', () async {
      expect(
        () => repository.getVisit(visitId: ' '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: NOT_FOUND for unknown visit', () async {
      client.rpcResults['get_visit'] = {'success': false, 'error_code': 'NOT_FOUND', 'error_message': 'Missing'};

      expect(
        () => repository.getVisit(visitId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });
  });
}
