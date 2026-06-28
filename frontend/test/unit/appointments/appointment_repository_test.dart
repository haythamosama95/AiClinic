import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository (Phase 2 foundation)', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: getAppointment calls RPC with appointment id', () async {
      final detail = await repository.getAppointment(appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

      expect(detail.patientName, 'Test Patient');
      expect(detail.status, AppointmentStatus.scheduled);
      expect(client.lastFunction, 'get_appointment');
      expect(client.lastParams?['p_appointment_id'], 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
    });

    test('stupid usage: blank appointment id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getAppointment(appointmentId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('trivial: getSettings calls RPC with branch id', () async {
      final settings = await repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444');

      expect(settings.defaultDurationMinutes, 30);
      expect(client.lastFunction, 'get_appointment_settings');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
    });

    test('stupid usage: blank branch id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getSettings(branchId: '  '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('advanced: setDefaultDuration sends org-wide when branch omitted', () async {
      final minutes = await repository.setDefaultDuration(durationMinutes: 45);

      expect(minutes, 45);
      expect(client.lastFunction, 'set_appointment_default_duration');
      expect(client.lastParams?['p_duration_minutes'], 45);
      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('edge case: setDefaultDuration rejects out-of-range minutes', () async {
      expect(
        () => repository.setDefaultDuration(durationMinutes: 4),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: setDefaultDuration throws when response omits saved minutes', () async {
      client.rpcResults['set_appointment_default_duration'] = {'success': true, 'data': <String, dynamic>{}};

      expect(() => repository.setDefaultDuration(durationMinutes: 45), throwsA(isA<StateError>()));
    });

    test('regression: setDefaultDuration throws when success has null duration field', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': null},
      };

      expect(() => repository.setDefaultDuration(durationMinutes: 45), throwsA(isA<StateError>()));
    });

    test('trivial: createAppointment planned sends type and start time', () async {
      final start = DateTime.utc(2026, 6, 1, 10);
      final result = await repository.createAppointment(
        branchId: '44444444-4444-4444-8444-444444444444',
        patientId: '11111111-1111-4111-8111-111111111111',
        doctorId: '22222222-2222-4222-8222-222222222222',
        type: AppointmentType.planned,
        startTime: start,
        durationMinutes: 30,
      );

      expect(result.type, AppointmentType.planned);
      expect(result.status, AppointmentStatus.scheduled);
      expect(client.lastParams?['p_type'], 'planned');
      expect(client.lastParams?['p_start_time'], start.toIso8601String());
    });

    test('stupid usage: planned create without start time throws INVALID_INPUT', () async {
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

    test('regression: SCHEDULE_CONFLICT surfaces from RPC', () async {
      client.rpcResults['create_appointment'] = {
        'success': false,
        'error_code': 'SCHEDULE_CONFLICT',
        'error_message': 'Overlap',
      };

      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 1, 10),
          durationMinutes: 30,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'SCHEDULE_CONFLICT')),
      );
    });

    test('trivial: listAppointments parses items', () async {
      final items = await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(items, hasLength(1));
      expect(items.first.patientName, 'Test Patient');
      expect(client.lastFunction, 'list_appointments');
    });

    test('invalid state: list with inverted range throws INVALID_INPUT', () async {
      expect(
        () => repository.listAppointments(
          branchId: '44444444-4444-4444-8444-444444444444',
          from: DateTime.utc(2026, 6, 2),
          to: DateTime.utc(2026, 6, 1),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('advanced: updateAppointmentStatus forwards wire value', () async {
      final status = await repository.updateAppointmentStatus(
        appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        newStatus: AppointmentStatus.checkedIn,
      );

      expect(status, AppointmentStatus.checkedIn);
      expect(client.lastParams?['p_new_status'], 'checked_in');
    });

    test('advanced: cancelAppointment forwards optional reason', () async {
      final status = await repository.cancelAppointment(
        appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        reason: 'Patient called',
      );

      expect(status, AppointmentStatus.cancelled);
      expect(client.lastFunction, 'cancel_appointment');
      expect(client.lastParams?['p_reason'], 'Patient called');
    });

    test('stupid usage: notes over 2000 chars rejected locally', () async {
      expect(
        () => repository.createAppointment(
          branchId: '44444444-4444-4444-8444-444444444444',
          patientId: '11111111-1111-4111-8111-111111111111',
          doctorId: '22222222-2222-4222-8222-222222222222',
          type: AppointmentType.planned,
          startTime: DateTime.utc(2026, 6, 1, 10),
          notes: 'x' * 2001,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });
  });

  group('AppointmentRepository (011 simplified slots)', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: getSimplifiedBookingSlots calls RPC with branch, date, and doctor', () async {
      final localDate = DateTime(2026, 6, 27);
      final slots = await repository.getSimplifiedBookingSlots(
        branchId: '44444444-4444-4444-8444-444444444444',
        localDate: localDate,
        preferredDoctorId: '22222222-2222-4222-8222-222222222222',
      );

      expect(client.lastFunction, 'get_simplified_booking_slots');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_local_date'], '2026-06-27');
      expect(client.lastParams?['p_preferred_doctor_id'], '22222222-2222-4222-8222-222222222222');
      expect(slots.defaultDurationMinutes, 30);
      expect(slots.blocks, hasLength(1));
      expect(slots.blocks.first.state, SlotAvailabilityState.available);
    });

    test('advanced: getSimplifiedBookingSlots parses alternate and unavailable states', () async {
      client.rpcResults['get_simplified_booking_slots'] = {
        'success': true,
        'data': {
          'default_duration_minutes': 15,
          'blocks': [
            {
              'start_time': '2026-06-27T09:00:00.000',
              'end_time': '2026-06-27T09:15:00.000',
              'state': 'alternate_doctors_available',
              'available_doctor_ids': ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'],
            },
            {
              'start_time': '2026-06-27T09:15:00.000',
              'end_time': '2026-06-27T09:30:00.000',
              'state': 'fully_unavailable',
              'available_doctor_ids': [],
            },
          ],
        },
      };

      final slots = await repository.getSimplifiedBookingSlots(
        branchId: '44444444-4444-4444-8444-444444444444',
        localDate: DateTime(2026, 6, 27),
        preferredDoctorId: '22222222-2222-4222-8222-222222222222',
      );

      expect(slots.defaultDurationMinutes, 15);
      expect(slots.blocks, hasLength(2));
      expect(slots.blocks[0].state, SlotAvailabilityState.alternateDoctorsAvailable);
      expect(slots.blocks[0].availableDoctorIds, ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']);
      expect(slots.blocks[1].state, SlotAvailabilityState.fullyUnavailable);
    });

    test('stupid usage: blank branch id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getSimplifiedBookingSlots(
          branchId: '  ',
          localDate: DateTime(2026, 6, 27),
          preferredDoctorId: '22222222-2222-4222-8222-222222222222',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: blank preferred doctor id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.getSimplifiedBookingSlots(
          branchId: '44444444-4444-4444-8444-444444444444',
          localDate: DateTime(2026, 6, 27),
          preferredDoctorId: '  ',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('regression: malformed slot response throws StateError', () async {
      client.rpcResults['get_simplified_booking_slots'] = {
        'success': true,
        'data': {'default_duration_minutes': null},
      };

      expect(
        () => repository.getSimplifiedBookingSlots(
          branchId: '44444444-4444-4444-8444-444444444444',
          localDate: DateTime(2026, 6, 27),
          preferredDoctorId: '22222222-2222-4222-8222-222222222222',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: RPC failure surfaces from getSimplifiedBookingSlots', () async {
      client.rpcResults['get_simplified_booking_slots'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Date out of range',
      };

      expect(
        () => repository.getSimplifiedBookingSlots(
          branchId: '44444444-4444-4444-8444-444444444444',
          localDate: DateTime(2026, 6, 27),
          preferredDoctorId: '22222222-2222-4222-8222-222222222222',
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });
  });
}
