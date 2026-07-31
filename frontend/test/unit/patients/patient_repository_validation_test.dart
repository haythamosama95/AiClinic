import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository validation & parsing (US1/US3)', () {
    late PatientRpcTestClient client;
    late PatientRepositoryImpl repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepositoryImpl(client);
    });

    group('searchPatients branch scope', () {
      test('stupid usage: null branchId with thisBranch throws ArgumentError before RPC', () async {
        expect(
          () => repository.searchPatients(scope: PatientListScope.thisBranch),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'branchId is required when scope is thisBranch',
            ),
          ),
        );
        expect(client.lastFunction, isNull);
      });

      test('stupid usage: empty branchId with thisBranch throws ArgumentError before RPC', () async {
        expect(
          () => repository.searchPatients(scope: PatientListScope.thisBranch, branchId: '   '),
          throwsA(isA<ArgumentError>()),
        );
        expect(client.lastFunction, isNull);
      });
    });

    group('checkDuplicates phone digit validation', () {
      test('stupid usage: fewer than 8 digits throws INVALID_INPUT before RPC', () async {
        expect(
          () => repository.checkDuplicates(phone: '1234567'),
          throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
        );
        expect(client.lastFunction, isNull);
      });

      test('stupid usage: more than 15 digits throws INVALID_INPUT before RPC', () async {
        expect(
          () => repository.checkDuplicates(phone: '1234567890123456'),
          throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
        );
        expect(client.lastFunction, isNull);
      });

      test('edge case: non-digit characters are stripped before digit count', () async {
        expect(
          () => repository.checkDuplicates(phone: '+1 (234) 567'),
          throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
        );
        expect(client.lastFunction, isNull);
      });

      test('trivial: exactly 8 digits proceeds to RPC', () async {
        await repository.checkDuplicates(phone: '12345678');

        expect(client.lastFunction, 'check_patient_duplicates');
        expect(client.lastParams?['p_phone'], '12345678');
      });

      test('trivial: exactly 15 digits proceeds to RPC', () async {
        await repository.checkDuplicates(phone: '123456789012345');

        expect(client.lastFunction, 'check_patient_duplicates');
        expect(client.lastParams?['p_phone'], '123456789012345');
      });
    });

    group('checkDuplicates excludePatientId', () {
      test('advanced: forwards p_exclude_patient_id when excludePatientId is provided', () async {
        await repository.checkDuplicates(
          phone: '201005551234',
          excludePatientId: '11111111-1111-4111-8111-111111111111',
        );

        expect(client.lastFunction, 'check_patient_duplicates');
        expect(client.lastParams?['p_exclude_patient_id'], '11111111-1111-4111-8111-111111111111');
      });

      test('advanced: omits p_exclude_patient_id when excludePatientId is not provided', () async {
        await repository.checkDuplicates(phone: '201005551234');

        expect(client.lastFunction, 'check_patient_duplicates');
        expect(client.lastParams?.containsKey('p_exclude_patient_id'), isFalse);
      });
    });

    group('createPatient mrn handling', () {
      test('edge case: whitespace-only mrn is omitted from RPC params', () async {
        await repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Ahmed Hassan',
            phone: '201005551234',
            mrn: '   ',
          ),
        );

        expect(client.lastFunction, 'create_patient');
        expect(client.lastParams?.containsKey('p_mrn'), isFalse);
      });

      test('invalid state: success payload missing patient_id throws StateError', () async {
        client.rpcResults['create_patient'] = {
          'success': true,
          'data': {'mrn': 'MRN-000042'},
        };

        expect(
          () => repository.createPatient(
            const CreatePatientInput(
              activeBranchId: '44444444-4444-4444-8444-444444444444',
              fullName: 'Ahmed Hassan',
              phone: '201005551234',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Patient was created but no patient_id was returned.',
            ),
          ),
        );
      });
    });

    group('updatePatient updated_at parsing', () {
      test('edge case: unparseable updated_at throws StateError', () async {
        client.rpcResults['update_patient'] = {
          'success': true,
          'data': {'patient_id': '11111111-1111-4111-8111-111111111111', 'updated_at': 'not-a-timestamp'},
        };

        expect(
          () => repository.updatePatient(
            UpdatePatientInput(
              patientId: '11111111-1111-4111-8111-111111111111',
              fullName: 'Ahmed Hassan',
              expectedUpdatedAt: DateTime.utc(2026, 1, 2),
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Patient updated_at could not be parsed: not-a-timestamp',
            ),
          ),
        );
      });
    });

    group('parseDuplicateCandidates', () {
      test('edge case: null raw value returns empty list', () {
        expect(PatientRepositoryImpl.parseDuplicateCandidates(null), isEmpty);
      });

      test('edge case: non-List raw value returns empty list', () {
        expect(PatientRepositoryImpl.parseDuplicateCandidates('not a list'), isEmpty);
        expect(PatientRepositoryImpl.parseDuplicateCandidates({'candidates': []}), isEmpty);
      });
    });
  });
}
