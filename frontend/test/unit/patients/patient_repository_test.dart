import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository', () {
    late PatientRpcTestClient client;
    late PatientRepository repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepository(client);
    });

    test('searchPatients sends branch scope and query', () async {
      await repository.searchPatients(
        query: '  ahmed  ',
        scope: PatientListScope.thisBranch,
        branchId: '44444444-4444-4444-8444-444444444444',
        limit: 10,
        offset: 5,
      );

      expect(client.lastFunction, 'search_patients');
      expect(client.lastParams?['p_query'], 'ahmed');
      expect(client.lastParams?['p_scope'], 'branch');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_limit'], 10);
      expect(client.lastParams?['p_offset'], 5);
    });

    test('searchPatients organization scope omits branch id', () async {
      await repository.searchPatients(scope: PatientListScope.allBranches);

      expect(client.lastParams?['p_scope'], 'organization');
      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('getPatient parses detail row', () async {
      final detail = await repository.getPatient('11111111-1111-4111-8111-111111111111');

      expect(detail.id, '11111111-1111-4111-8111-111111111111');
      expect(detail.fullName, 'Test Patient');
      expect(detail.branchName, 'Main');
    });

    test('checkDuplicates parses candidate list', () async {
      final candidates = await repository.checkDuplicates(fullName: 'Test', phone: '201234567890');

      expect(candidates, hasLength(1));
      expect(candidates.first.fullName, 'Duplicate');
    });

    test('createPatient returns patient id', () async {
      final id = await repository.createPatient(
        const CreatePatientInput(
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          fullName: 'New Patient',
          phone: '201000000001',
        ),
      );

      expect(id, '33333333-3333-4333-8333-333333333333');
      expect(client.lastParams?['p_full_name'], 'New Patient');
    });

    test('stupid usage: blank name throws before RPC on create', () async {
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

    test('updatePatient returns parsed updated_at', () async {
      final updatedAt = await repository.updatePatient(
        UpdatePatientInput(
          patientId: '11111111-1111-4111-8111-111111111111',
          fullName: 'Updated',
          expectedUpdatedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      expect(updatedAt, DateTime.utc(2026, 1, 3));
      expect(client.lastParams?['p_expected_updated_at'], '2026-01-02T00:00:00.000Z');
    });

    test('advanced: DUPLICATE_WARNING propagates as RpcFailure', () async {
      client.rpcResults['create_patient'] = {
        'success': false,
        'error_code': 'DUPLICATE_WARNING',
        'error_message': 'Similar patients found',
        'data': {'candidates': []},
      };

      expect(
        () => repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Dup',
            phone: '201000000001',
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'DUPLICATE_WARNING')),
      );
    });

    test('archivePatient invokes RPC', () async {
      await repository.archivePatient('11111111-1111-4111-8111-111111111111');

      expect(client.lastFunction, 'archive_patient');
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
    });
  });
}
