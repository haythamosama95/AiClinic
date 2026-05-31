import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  group('VisitRepository.createVisit', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: forwards appointment id to create_visit RPC', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      final result = await repository.createVisit(appointmentId: appointmentId);

      expect(client.lastFunction, 'create_visit');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(result.visitId, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
      expect(result.status, 'in_progress');
      expect(result.appointmentId, appointmentId);
    });

    test('advanced: includes doctor id when provided', () async {
      const doctorId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

      await repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', doctorId: doctorId);

      expect(client.lastParams?['p_doctor_id'], doctorId);
    });

    test('advanced: omits doctor param when blank', () async {
      await repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', doctorId: '   ');

      expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
    });

    test('invalid state: APPOINTMENT_NOT_ELIGIBLE surfaces from RPC', () async {
      client.rpcResults['create_visit'] = {
        'success': false,
        'error_code': 'APPOINTMENT_NOT_ELIGIBLE',
        'error_message': 'Not eligible',
      };

      expect(
        () => repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'APPOINTMENT_NOT_ELIGIBLE')),
      );
    });

    test('invalid state: VISIT_ALREADY_EXISTS surfaces from RPC', () async {
      client.rpcResults['create_visit'] = {
        'success': false,
        'error_code': 'VISIT_ALREADY_EXISTS',
        'error_message': 'Duplicate',
      };

      expect(
        () => repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'VISIT_ALREADY_EXISTS')),
      );
    });

    test('invalid state: DOCTOR_REQUIRED surfaces from RPC', () async {
      client.rpcResults['create_visit'] = {
        'success': false,
        'error_code': 'DOCTOR_REQUIRED',
        'error_message': 'Pick a doctor',
      };

      expect(
        () => repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'DOCTOR_REQUIRED')),
      );
    });

    test('stupid usage: blank appointment id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.createVisit(appointmentId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['create_visit'] = {
        'success': true,
        'data': {'visit_id': null},
      };

      expect(
        () => repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: FORBIDDEN permission denial propagates', () async {
      client.rpcResults['create_visit'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Permission denied',
      };

      expect(
        () => repository.createVisit(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('VisitRepository.getVisitByAppointment', () {
    late VisitRpcTestClient client;
    late VisitRepository repository;

    setUp(() {
      client = VisitRpcTestClient();
      repository = VisitRepository(client);
    });

    test('trivial: returns empty link when no visit exists', () async {
      final link = await repository.getVisitByAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

      expect(client.lastFunction, 'get_visit_by_appointment');
      expect(link.visitId, isNull);
      expect(link.status, isNull);
    });

    test('advanced: parses visit id and status from RPC', () async {
      client.rpcResults['get_visit_by_appointment'] = {
        'success': true,
        'data': {'visit_id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'status': 'in_progress'},
      };

      final link = await repository.getVisitByAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

      expect(link.visitId, 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
      expect(link.status, 'in_progress');
    });

    test('stupid usage: blank appointment id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getVisitByAppointment(appointmentId: ''),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('regression: null data maps to empty result', () async {
      client.rpcResults['get_visit_by_appointment'] = {'success': true, 'data': null};

      final link = await repository.getVisitByAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

      expect(link.visitId, isNull);
      expect(link.status, isNull);
    });
  });
}
