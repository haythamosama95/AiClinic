import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository.getPatient (US3)', () {
    late PatientRpcTestClient client;
    late PatientRepository repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepository(client);
    });

    test('trivial: invokes get_patient with trimmed id and parses profile', () async {
      final detail = await repository.getPatient('  11111111-1111-4111-8111-111111111111  ');

      expect(client.lastFunction, 'get_patient');
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
      expect(detail.id, '11111111-1111-4111-8111-111111111111');
      expect(detail.fullName, 'Test Patient');
      expect(detail.branchName, 'Main');
    });

    test('advanced: parses optional demographic and audit fields', () async {
      client.rpcResults['get_patient'] = {
        'success': true,
        'data': {
          'id': '11111111-1111-4111-8111-111111111111',
          'full_name': 'Sara Ali',
          'phone': '201111111111',
          'date_of_birth': '1985-03-20',
          'gender': 'female',
          'marital_status': 'widowed',
          'notes': 'Penicillin allergy',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'branch_name': 'Main',
          'created_at': '2026-01-01T08:00:00.000Z',
          'updated_at': '2026-01-02T09:30:00.000Z',
          'created_by_display': 'Reception',
        },
      };

      final detail = await repository.getPatient('11111111-1111-4111-8111-111111111111');

      expect(detail.gender, PatientGender.female);
      expect(detail.maritalStatus, PatientMaritalStatus.widowed);
      expect(detail.notes, 'Penicillin allergy');
      expect(detail.createdByDisplay, 'Reception');
      expect(detail.dateOfBirth, DateTime(1985, 3, 20));
    });

    test('stupid usage: blank patient id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getPatient('   '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['get_patient'] = {
        'success': true,
        'data': {'id': 'bad', 'full_name': ''},
      };

      expect(() => repository.getPatient('bad'), throwsA(isA<StateError>()));
    });

    test('invalid state: PATIENT_ARCHIVED propagates as RpcFailure', () async {
      client.rpcResults['get_patient'] = {
        'success': false,
        'error_code': 'PATIENT_ARCHIVED',
        'error_message': 'This patient is archived.',
      };

      expect(
        () => repository.getPatient('11111111-1111-4111-8111-111111111111'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ARCHIVED')),
      );
    });

    test('invalid state: NOT_FOUND propagates as RpcFailure', () async {
      client.rpcResults['get_patient'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Patient was not found.',
      };

      expect(
        () => repository.getPatient('99999999-9999-4999-8999-999999999999'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    test('regression: unexpected shape after success still throws StateError', () async {
      client.rpcResults['get_patient'] = {'success': true, 'data': {}};

      expect(
        () => repository.getPatient('11111111-1111-4111-8111-111111111111'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('unexpected shape'))),
      );
    });
  });
}
