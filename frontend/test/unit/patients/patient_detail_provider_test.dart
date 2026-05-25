import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

void main() {
  group('patientDetailProvider', () {
    late PatientRpcTestClient client;

    ProviderContainer container() {
      return ProviderContainer(
        overrides: [patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client))],
      );
    }

    setUp(() {
      client = PatientRpcTestClient();
    });

    test('loads patient detail for valid id', () async {
      final c = container();
      addTearDown(c.dispose);

      final detail = await c.read(patientDetailProvider('11111111-1111-4111-8111-111111111111').future);

      expect(detail, isA<PatientDetail>());
      expect(detail.fullName, 'Test Patient');
      expect(client.lastFunction, 'get_patient');
    });

    test('trims whitespace from patient id', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientDetailProvider('  11111111-1111-4111-8111-111111111111  ').future);

      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
    });

    test('empty id throws StateError without calling RPC', () async {
      final c = container();
      addTearDown(c.dispose);

      await expectLater(
        c.read(patientDetailProvider('').future),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Patient id is required.')),
      );
      expect(client.lastFunction, isNull);
    });

    test('whitespace-only id throws StateError', () async {
      final c = container();
      addTearDown(c.dispose);

      await expectLater(
        c.read(patientDetailProvider('   ').future),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Patient id is required.')),
      );
      expect(client.lastFunction, isNull);
    });

    test('NOT_FOUND RpcFailure maps to user-facing StateError', () async {
      client.rpcResults['get_patient'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Patient was not found.',
      };

      final c = container();
      addTearDown(c.dispose);

      await expectLater(
        c.read(patientDetailProvider('99999999-9999-4999-8999-999999999999').future),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'Patient was not found or you do not have access.'),
        ),
      );
    });

    test('PATIENT_ARCHIVED maps to archived message', () {
      expect(
        patientMessageForRpc(
          RpcFailure(
            const RpcResult(success: false, errorCode: 'PATIENT_ARCHIVED', errorMessage: 'This patient is archived.'),
          ),
        ),
        contains('archived'),
      );
    });

    test('FORBIDDEN maps to permission message', () async {
      client.rpcResults['get_patient'] = {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Forbidden'};

      final c = container();
      addTearDown(c.dispose);

      await expectLater(
        c.read(patientDetailProvider('11111111-1111-4111-8111-111111111111').future),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'You do not have permission to perform this action.'),
        ),
      );
    });

    test('different ids produce independent provider instances', () async {
      final c = container();
      addTearDown(c.dispose);

      client.rpcResults['get_patient'] = {
        'success': true,
        'data': {
          'id': 'aaa',
          'full_name': 'Patient A',
          'branch_id': 'b1',
          'branch_name': 'Main',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      };

      final detailA = await c.read(patientDetailProvider('aaa').future);
      expect(detailA.fullName, 'Patient A');

      client.rpcResults['get_patient'] = {
        'success': true,
        'data': {
          'id': 'bbb',
          'full_name': 'Patient B',
          'branch_id': 'b1',
          'branch_name': 'Main',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
      };

      final detailB = await c.read(patientDetailProvider('bbb').future);
      expect(detailB.fullName, 'Patient B');
    });
  });
}
