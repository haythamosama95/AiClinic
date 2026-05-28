import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.createAppointment (walk_in, US2)', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: walk-in sends type and doctor, returns checked-in with assigned slot', () async {
      client.rpcResults['create_appointment'] = {
        'success': true,
        'data': {
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'start_time': '2026-06-01T14:00:00.000Z',
          'end_time': '2026-06-01T14:20:00.000Z',
          'status': 'checked_in',
          'type': 'walk_in',
        },
      };

      final result = await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        doctorId: '22222222-2222-4222-8222-222222222222',
        type: AppointmentType.walkIn,
        durationMinutes: 20,
      );

      expect(result.type, AppointmentType.walkIn);
      expect(result.status, AppointmentStatus.checkedIn);
      expect(client.lastParams?['p_type'], 'walk_in');
      expect(client.lastParams?['p_doctor_id'], '22222222-2222-4222-8222-222222222222');
    });

    test('advanced: walk-in ignores client-provided start time', () async {
      final requestedStart = DateTime.utc(2026, 6, 1, 8, 30);
      await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        doctorId: '22222222-2222-4222-8222-222222222222',
        type: AppointmentType.walkIn,
        startTime: requestedStart,
        durationMinutes: 15,
      );

      expect(client.lastParams?.containsKey('p_start_time'), isFalse);
    });

    test('advanced: walk-in without doctor omits p_doctor_id param', () async {
      final result = await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        type: AppointmentType.walkIn,
        durationMinutes: 15,
      );

      expect(result.type, AppointmentType.walkIn);
      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?['p_doctor_id'], isNull);
    });

    test('edge case: duration above max is rejected locally', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.walkIn,
          durationMinutes: 241,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: NO_SLOT_AVAILABLE propagates with stable error code', () async {
      client.rpcResults['create_appointment'] = {
        'success': false,
        'error_code': 'NO_SLOT_AVAILABLE',
        'error_message': 'No free slot today',
      };

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.walkIn,
          durationMinutes: 15,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NO_SLOT_AVAILABLE')),
      );
    });

    test('regression: PATIENT_ALREADY_BOOKED_SAME_DAY propagates with stable error code', () async {
      client.rpcResults['create_appointment'] = {
        'success': false,
        'error_code': 'PATIENT_ALREADY_BOOKED_SAME_DAY',
        'error_message': 'Already booked',
      };

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.walkIn,
          durationMinutes: 15,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ALREADY_BOOKED_SAME_DAY')),
      );
    });

    test('stupid usage: blank branch id is rejected before RPC', () async {
      expect(
        () => repository.createAppointment(
          branchId: '   ',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.walkIn,
          durationMinutes: 15,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });
  });
}
