import 'dart:async';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ThrowingPostgrestRpc extends Fake implements PostgrestFilterBuilder<dynamic> {
  _ThrowingPostgrestRpc(this.exception);

  final PostgrestException exception;

  @override
  Future<R> then<R>(FutureOr<R> Function(dynamic value) onValue, {Function? onError}) {
    return Future<dynamic>.error(exception).then(onValue, onError: onError);
  }
}

class _PostgrestErrorClient extends Fake implements SupabaseClient {
  _PostgrestErrorClient({required this.exception});

  final PostgrestException exception;
  String? lastFunction;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    lastFunction = fn;
    return _ThrowingPostgrestRpc(exception) as PostgrestFilterBuilder<T>;
  }
}

PostgrestException _pgrst202({String fn = 'search_patients'}) {
  return PostgrestException(
    message: 'Could not find the function public.$fn(p_scope, p_limit, p_offset) in the schema cache',
    code: 'PGRST202',
  );
}

PostgrestException _otherException() {
  return PostgrestException(message: 'permission denied for function search_patients', code: '42501');
}

void main() {
  group('PatientRepository PostgrestException handling', () {
    test('PGRST202 is mapped to RPC_NOT_APPLIED with migration guidance', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202());
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.searchPatients(scope: PatientListScope.allBranches),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('migration'))
              .having((e) => e.message, 'message', contains('search_patients')),
        ),
      );
    });

    test('PGRST202 on get_patient mentions correct function name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202(fn: 'get_patient'));
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.getPatient('some-id'),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('get_patient')),
        ),
      );
    });

    test('PGRST202 on create_patient mentions correct function name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202(fn: 'create_patient'));
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.createPatient(
          const CreatePatientInput(activeBranchId: 'b1', fullName: 'Test', phone: '201000000001'),
        ),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('create_patient')),
        ),
      );
    });

    test('PGRST202 on update_patient mentions correct function name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202(fn: 'update_patient'));
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.updatePatient(
          UpdatePatientInput(patientId: 'p1', fullName: 'Updated', expectedUpdatedAt: DateTime.utc(2026)),
        ),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('update_patient')),
        ),
      );
    });

    test('PGRST202 on archive_patient mentions correct function name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202(fn: 'archive_patient'));
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.archivePatient('p1'),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('archive_patient')),
        ),
      );
    });

    test('PGRST202 on check_patient_duplicates mentions correct function name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202(fn: 'check_patient_duplicates'));
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.checkDuplicates(fullName: 'Test'),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('check_patient_duplicates')),
        ),
      );
    });

    test('"Could not find the function" message without PGRST202 code still triggers', () async {
      final exception = PostgrestException(
        message: 'Could not find the function public.search_patients(...)',
        code: null,
      );
      final client = _PostgrestErrorClient(exception: exception);
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.searchPatients(scope: PatientListScope.allBranches),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_NOT_APPLIED')),
      );
    });

    test('non-PGRST202 PostgrestException is mapped to RpcFailure', () async {
      final client = _PostgrestErrorClient(exception: _otherException());
      final repository = PatientRepositoryImpl(client);

      expect(
        () => repository.searchPatients(scope: PatientListScope.allBranches),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_NOT_CONFIGURED')),
      );
    });

    test('RPC_NOT_APPLIED message includes migration file name', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202());
      final repository = PatientRepositoryImpl(client);

      try {
        await repository.searchPatients(scope: PatientListScope.allBranches);
        fail('Expected RpcFailure');
      } on RpcFailure catch (e) {
        expect(e.message, contains('20260523140000_patient_management.sql'));
        expect(e.message, contains('search_patients'));
      }
    });
  });
}
