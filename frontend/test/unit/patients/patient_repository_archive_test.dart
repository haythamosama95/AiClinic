import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('PatientRepository archivePatient (US5)', () {
    late PatientRpcTestClient client;
    late PatientRepository repository;

    setUp(() {
      client = PatientRpcTestClient();
      repository = PatientRepository(client);
    });

    test('trivial: archivePatient invokes RPC with patient id', () async {
      await repository.archivePatient('11111111-1111-4111-8111-111111111111');

      expect(client.lastFunction, 'archive_patient');
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
    });

    test('edge case: PATIENT_ARCHIVED when already archived', () async {
      client.rpcResults['archive_patient'] = {
        'success': false,
        'error_code': 'PATIENT_ARCHIVED',
        'error_message': 'Already archived',
      };

      expect(
        () => repository.archivePatient('11111111-1111-4111-8111-111111111111'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ARCHIVED')),
      );
    });

    test('invalid state: FORBIDDEN without delete permission', () async {
      client.rpcResults['archive_patient'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Forbidden',
      };

      expect(
        () => repository.archivePatient('11111111-1111-4111-8111-111111111111'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });

    test('stupid usage: NOT_FOUND for unknown patient', () async {
      client.rpcResults['archive_patient'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Not found',
      };

      expect(
        () => repository.archivePatient('99999999-9999-4999-8999-999999999999'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    test('regression: success returns without parsing body fields', () async {
      client.rpcResults['archive_patient'] = {'success': true, 'data': {}};

      await expectLater(repository.archivePatient('11111111-1111-4111-8111-111111111111'), completes);
    });
  });
}
