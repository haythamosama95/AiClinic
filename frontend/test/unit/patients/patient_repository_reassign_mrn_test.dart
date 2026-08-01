import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository reassignPatientMrn', () {
    late PatientRpcTestClient client;
    late PatientRepositoryImpl repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepositoryImpl(client);
    });

    test('trivial: invokes reassign_patient_mrn with trimmed params and returns mrn', () async {
      const patientId = '11111111-1111-4111-8111-111111111111';
      const newMrn = 'MRN-000099';

      final assignedMrn = await repository.reassignPatientMrn(
        patientId: '  $patientId  ',
        newMrn: '  $newMrn  ',
      );

      expect(assignedMrn, newMrn);
      expect(client.lastFunction, 'reassign_patient_mrn');
      expect(client.lastParams?['p_patient_id'], patientId);
      expect(client.lastParams?['p_new_mrn'], newMrn);
    });

    test('stupid usage: blank patientId throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.reassignPatientMrn(patientId: '   ', newMrn: 'MRN-000099'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: blank newMrn throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.reassignPatientMrn(
          patientId: '11111111-1111-4111-8111-111111111111',
          newMrn: '   ',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('invalid state: success payload missing mrn throws StateError', () async {
      client.rpcResults['reassign_patient_mrn'] = {
        'success': true,
        'data': {'patient_id': '11111111-1111-4111-8111-111111111111'},
      };

      expect(
        () => repository.reassignPatientMrn(
          patientId: '11111111-1111-4111-8111-111111111111',
          newMrn: 'MRN-000099',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'MRN was reassigned but no mrn was returned.',
          ),
        ),
      );
    });

    test('invalid state: MRN_EXISTS propagates as RpcFailure', () async {
      client.rpcResults['reassign_patient_mrn'] = {
        'success': false,
        'error_code': 'MRN_EXISTS',
        'error_message': 'Another patient already uses this MRN.',
      };

      expect(
        () => repository.reassignPatientMrn(
          patientId: '11111111-1111-4111-8111-111111111111',
          newMrn: 'MRN-000099',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'MRN_EXISTS')),
      );
    });
  });
}
