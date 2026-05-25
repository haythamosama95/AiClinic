import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository create & duplicates (US1)', () {
    late PatientRpcTestClient client;
    late PatientRepositoryImpl repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepositoryImpl(client);
    });

    test('trivial: createPatient returns patient_id and sends branch + name + phone', () async {
      final id = await repository.createPatient(
        const CreatePatientInput(
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          fullName: 'Ahmed Hassan',
          phone: '201005551234',
        ),
      );

      expect(id, '33333333-3333-4333-8333-333333333333');
      expect(client.lastFunction, 'create_patient');
      expect(client.lastParams?['p_active_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_full_name'], 'Ahmed Hassan');
      expect(client.lastParams?['p_phone'], '201005551234');
      expect(client.lastParams?['p_acknowledge_duplicate'], false);
    });

    test('advanced: optional fields are trimmed and encoded', () async {
      await repository.createPatient(
        CreatePatientInput(
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          fullName: '  Full  ',
          phone: '  +20 100 555 1234  ',
          dateOfBirth: DateTime(1990, 5, 15),
          gender: PatientGender.male,
          maritalStatus: PatientMaritalStatus.married,
          notes: '  note  ',
        ),
      );

      expect(client.lastParams?['p_full_name'], 'Full');
      expect(client.lastParams?['p_phone'], '+20 100 555 1234');
      expect(client.lastParams?['p_date_of_birth'], '1990-05-15');
      expect(client.lastParams?['p_gender'], 'male');
      expect(client.lastParams?['p_marital_status'], 'married');
      expect(client.lastParams?['p_notes'], 'note');
    });

    test('advanced: acknowledge_duplicate flag is forwarded', () async {
      await repository.createPatient(
        const CreatePatientInput(
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          fullName: 'Dup',
          phone: '201000000001',
          acknowledgeDuplicate: true,
        ),
      );

      expect(client.lastParams?['p_acknowledge_duplicate'], true);
    });

    test('stupid usage: blank name throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: '   ',
            phone: '201000000001',
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: blank phone throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Ahmed',
            phone: '   ',
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: DUPLICATE_WARNING includes parsed candidates', () async {
      client.rpcResults['create_patient'] = {
        'success': false,
        'error_code': 'DUPLICATE_WARNING',
        'error_message': 'Similar patients found',
        'data': {
          'candidates': [
            {
              'id': '22222222-2222-4222-8222-222222222222',
              'full_name': 'Ahmed Hassan',
              'phone': '201005551234',
              'branch_name': 'Main',
            },
          ],
        },
      };

      RpcFailure? failure;
      try {
        await repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Ahmed Hassan',
            phone: '201005551234',
          ),
        );
      } on RpcFailure catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure!.code, 'DUPLICATE_WARNING');
      final candidates = PatientRepositoryImpl.parseDuplicateCandidates(failure.result.data?['candidates']);
      expect(candidates, hasLength(1));
      expect(candidates.first.fullName, 'Ahmed Hassan');
    });

    test('checkDuplicates sends all provided fields', () async {
      await repository.checkDuplicates(fullName: '  Ahmed  ', phone: ' 2010 ', dateOfBirth: DateTime(1990, 5, 15));

      expect(client.lastFunction, 'check_patient_duplicates');
      expect(client.lastParams?['p_full_name'], 'Ahmed');
      expect(client.lastParams?['p_phone'], '2010');
      expect(client.lastParams?['p_date_of_birth'], '1990-05-15');
    });

    test('checkDuplicates parses multiple candidates', () async {
      client.rpcResults['check_patient_duplicates'] = {
        'success': true,
        'data': {
          'candidates': [
            {'id': 'a', 'full_name': 'One', 'branch_name': 'Main'},
            {'id': 'b', 'full_name': 'Two', 'branch_name': 'Second'},
          ],
        },
      };

      final candidates = await repository.checkDuplicates(phone: '2010');

      expect(candidates, hasLength(2));
    });

    test('regression: malformed candidate rows are skipped', () async {
      client.rpcResults['check_patient_duplicates'] = {
        'success': true,
        'data': {
          'candidates': [
            {'id': 'a', 'full_name': 'Valid', 'branch_name': 'Main'},
            {'id': 'bad'},
          ],
        },
      };

      final candidates = await repository.checkDuplicates(phone: '2010');

      expect(candidates, hasLength(1));
    });
  });
}
