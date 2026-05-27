import 'dart:async';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
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

PostgrestException _pgrst202({String fn = 'get_appointment_settings'}) {
  return PostgrestException(
    message: 'Could not find the function public.$fn(p_branch_id) in the schema cache',
    code: 'PGRST202',
  );
}

PostgrestException _authInternalPermissionDenied() {
  return PostgrestException(message: 'permission denied for schema auth_internal', code: '42501');
}

void main() {
  group('AppointmentRepository PostgrestException handling', () {
    test('PGRST202 maps to RPC_NOT_APPLIED with appointment migration hint', () async {
      final client = _PostgrestErrorClient(exception: _pgrst202());
      final repository = AppointmentRepository(client);

      expect(
        () => repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444'),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_APPLIED')
              .having((e) => e.message, 'message', contains('20260526140000_appointment_management.sql'))
              .having((e) => e.message, 'message', contains('get_appointment_settings')),
        ),
      );
    });

    test('42501 auth_internal permission denied maps to RPC_NOT_CONFIGURED', () async {
      final client = _PostgrestErrorClient(exception: _authInternalPermissionDenied());
      final repository = AppointmentRepository(client);

      expect(
        () => repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444'),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'RPC_NOT_CONFIGURED')
              .having((e) => e.message, 'message', contains('20260526140000_appointment_management.sql')),
        ),
      );
    });

    test('42501 on create_appointment surfaces RPC_NOT_CONFIGURED', () async {
      final client = _PostgrestErrorClient(exception: _authInternalPermissionDenied());
      final repository = AppointmentRepository(client);

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_NOT_CONFIGURED')),
      );
    });

    test('generic Postgrest error maps to RpcFailure with postgrest code', () async {
      final client = _PostgrestErrorClient(
        exception: PostgrestException(message: 'JWT expired', code: 'PGRST301'),
      );
      final repository = AppointmentRepository(client);

      expect(
        () => repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PGRST301')),
      );
    });
  });
}
