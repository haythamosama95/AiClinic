import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository createPatient MRN (US1)', () {
    late PatientRpcTestClient client;
    late PatientRepositoryImpl repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepositoryImpl(client);
    });

    test('returns CreatePatientResult with mrn from mocked RPC payload', () async {
      const expectedMrn = 'MRN-000099';
      const expectedPatientId = '33333333-3333-4333-8333-333333333333';
      client.rpcResults['create_patient'] = {
        'success': true,
        'data': {'patient_id': expectedPatientId, 'mrn': expectedMrn},
      };

      final result = await repository.createPatient(
        const CreatePatientInput(
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          fullName: 'Ahmed Hassan',
          phone: '201005551234',
        ),
      );

      expect(result.patientId, expectedPatientId);
      expect(result.mrn, expectedMrn);
      expect(client.lastFunction, 'create_patient');
    });

    test('RpcFailure does not return an MRN', () async {
      client.rpcResults['create_patient'] = {
        'success': false,
        'error_code': 'NETWORK_ERROR',
        'error_message': 'Backend unreachable',
      };

      expect(
        () => repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Ahmed Hassan',
            phone: '201005551234',
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NETWORK_ERROR')),
      );
    });

    test('success without mrn throws instead of fabricating a value', () async {
      client.rpcResults['create_patient'] = {
        'success': true,
        'data': {'patient_id': '33333333-3333-4333-8333-333333333333'},
      };

      expect(
        () => repository.createPatient(
          const CreatePatientInput(
            activeBranchId: '44444444-4444-4444-8444-444444444444',
            fullName: 'Ahmed Hassan',
            phone: '201005551234',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
