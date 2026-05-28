import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.createAppointment (planned, US1)', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: planned create sends branch, patient, doctor, type, start, duration', () async {
      final start = DateTime.utc(2026, 6, 15, 9);
      final result = await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        doctorId: '22222222-2222-4222-8222-222222222222',
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
        notes: 'Follow-up',
      );

      expect(result.type, AppointmentType.planned);
      expect(result.status, AppointmentStatus.scheduled);
      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
      expect(client.lastParams?['p_doctor_id'], '22222222-2222-4222-8222-222222222222');
      expect(client.lastParams?['p_type'], 'planned');
      expect(client.lastParams?['p_start_time'], start.toIso8601String());
      expect(client.lastParams?['p_duration_minutes'], 30);
      expect(client.lastParams?['p_notes'], 'Follow-up');
    });

    test('advanced: planned create without doctor sends null p_doctor_id', () async {
      final start = DateTime.utc(2026, 6, 16, 11);
      await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 20,
      );

      expect(client.lastParams?['p_doctor_id'], isNull);
    });

    test('regression: walk-in without doctor is allowed and sends null doctor', () async {
      await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        type: AppointmentType.walkIn,
        durationMinutes: 15,
      );
      expect(client.lastFunction, 'create_appointment');
      expect(client.lastParams?['p_doctor_id'], isNull);
    });

    test('advanced: omits duration when using server default from settings', () async {
      await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        doctorId: '22222222-2222-4222-8222-222222222222',
        type: AppointmentType.planned,
        startTime: DateTime.utc(2026, 6, 15, 10),
      );

      expect(client.lastParams?.containsKey('p_duration_minutes'), isFalse);
    });

    test('stupid usage: blank patient id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '  ',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('invalid state: planned without start time rejected locally', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('edge case: duration below minimum rejected locally', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
          durationMinutes: 4,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: SCHEDULE_CONFLICT propagates with stable code', () async {
      client.rpcResults['create_appointment'] = {
        'success': false,
        'error_code': 'SCHEDULE_CONFLICT',
        'error_message': 'Doctor schedule overlap',
      };

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
          durationMinutes: 30,
        ),
        throwsA(
          isA<RpcFailure>()
              .having((e) => e.code, 'code', 'SCHEDULE_CONFLICT')
              .having((e) => e.message, 'message', 'Doctor schedule overlap'),
        ),
      );
    });

    test('regression: PATIENT_ARCHIVED surfaces from RPC', () async {
      client.rpcResults['create_appointment'] = {
        'success': false,
        'error_code': 'PATIENT_ARCHIVED',
        'error_message': 'Archived',
      };

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ARCHIVED')),
      );
    });

    test('regression: PATIENT_ALREADY_BOOKED_SAME_DAY surfaces from RPC', () async {
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
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'PATIENT_ALREADY_BOOKED_SAME_DAY')),
      );
    });

    test('stupid usage: notes over 2000 chars rejected locally', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 15, 10),
          notes: 'x' * 2001,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });
  });
}
