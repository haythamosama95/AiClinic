import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository updatePatient (US4)', () {
    late PatientRpcTestClient client;
    late PatientRepository repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepository(client);
    });

    test('trivial: sends patient id, name, expected_updated_at, and phone', () async {
      final updatedAt = await repository.updatePatient(
        UpdatePatientInput(
          patientId: '11111111-1111-4111-8111-111111111111',
          fullName: 'Ahmed Hassan',
          expectedUpdatedAt: DateTime.utc(2026, 1, 2, 9, 30),
          phone: '209911112233',
        ),
      );

      expect(updatedAt, DateTime.utc(2026, 1, 3));
      expect(client.lastFunction, 'update_patient');
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
      expect(client.lastParams?['p_full_name'], 'Ahmed Hassan');
      expect(client.lastParams?['p_expected_updated_at'], '2026-01-02T09:30:00.000Z');
      expect(client.lastParams?['p_phone'], '209911112233');
      expect(client.lastParams?['p_acknowledge_duplicate'], false);
    });

    test('advanced: optional fields encoded on update', () async {
      await repository.updatePatient(
        UpdatePatientInput(
          patientId: '11111111-1111-4111-8111-111111111111',
          fullName: 'Updated',
          expectedUpdatedAt: DateTime.utc(2026, 1, 2),
          dateOfBirth: DateTime(1990, 5, 15),
          gender: PatientGender.female,
          maritalStatus: PatientMaritalStatus.single,
          notes: '  refreshed  ',
          acknowledgeDuplicate: true,
        ),
      );

      expect(client.lastParams?['p_date_of_birth'], '1990-05-15');
      expect(client.lastParams?['p_gender'], 'female');
      expect(client.lastParams?['p_marital_status'], 'single');
      expect(client.lastParams?['p_notes'], 'refreshed');
      expect(client.lastParams?['p_acknowledge_duplicate'], true);
    });

    test('stupid usage: blank name throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.updatePatient(
          UpdatePatientInput(
            patientId: '11111111-1111-4111-8111-111111111111',
            fullName: '   ',
            expectedUpdatedAt: DateTime.utc(2026, 1, 2),
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: STALE_PATIENT propagates as RpcFailure', () async {
      client.rpcResults['update_patient'] = {
        'success': false,
        'error_code': 'STALE_PATIENT',
        'error_message': 'This record was updated elsewhere.',
      };

      expect(
        () => repository.updatePatient(
          UpdatePatientInput(
            patientId: '11111111-1111-4111-8111-111111111111',
            fullName: 'Stale',
            expectedUpdatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.isStalePatient, 'isStalePatient', isTrue)
              .having((e) => e.code, 'code', 'STALE_PATIENT'),
        ),
      );
    });

    test('advanced: DUPLICATE_WARNING includes candidates', () async {
      client.rpcResults['update_patient'] = {
        'success': false,
        'error_code': 'DUPLICATE_WARNING',
        'error_message': 'Similar patients found',
        'data': {
          'candidates': [
            {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Other', 'branch_name': 'Second'},
          ],
        },
      };

      try {
        await repository.updatePatient(
          UpdatePatientInput(
            patientId: '11111111-1111-4111-8111-111111111111',
            fullName: 'Dup',
            expectedUpdatedAt: DateTime.utc(2026, 1, 2),
            phone: '209911112233',
          ),
        );
        fail('expected RpcFailure');
      } on RpcFailure catch (error) {
        expect(error.isDuplicateWarning, isTrue);
        expect(error.duplicateCandidates, hasLength(1));
        expect(error.duplicateCandidates.first.fullName, 'Other');
      }
    });

    test('invalid state: PATIENT_ARCHIVED on update', () async {
      client.rpcResults['update_patient'] = {
        'success': false,
        'error_code': 'PATIENT_ARCHIVED',
        'error_message': 'Archived',
      };

      expect(
        () => repository.updatePatient(
          UpdatePatientInput(
            patientId: '11111111-1111-4111-8111-111111111111',
            fullName: 'Archived',
            expectedUpdatedAt: DateTime.utc(2026, 1, 2),
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ARCHIVED')),
      );
    });

    test('regression: missing updated_at in success payload throws StateError', () async {
      client.rpcResults['update_patient'] = {
        'success': true,
        'data': {'patient_id': '11111111-1111-4111-8111-111111111111'},
      };

      expect(
        () => repository.updatePatient(
          UpdatePatientInput(
            patientId: '11111111-1111-4111-8111-111111111111',
            fullName: 'Ok',
            expectedUpdatedAt: DateTime.utc(2026, 1, 2),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
