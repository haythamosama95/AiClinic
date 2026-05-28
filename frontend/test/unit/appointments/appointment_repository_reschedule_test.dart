import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.rescheduleAppointment', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: forwards appointment id, start, and duration', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final start = DateTime.utc(2026, 6, 1, 12);

      final result = await repository.rescheduleAppointment(
        appointmentId: appointmentId,
        startTime: start,
        durationMinutes: 25,
      );

      expect(client.lastFunction, 'reschedule_appointment');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(client.lastParams?['p_start_time'], start.toUtc().toIso8601String());
      expect(client.lastParams?['p_duration_minutes'], 25);
      expect(client.lastParams?['p_end_time'], isNull);
      expect(result.appointmentId, appointmentId);
      expect(result.status, AppointmentStatus.scheduled);
      expect(result.type, AppointmentType.planned);
    });

    test('advanced: omits duration when not provided', () async {
      final start = DateTime.utc(2026, 6, 2, 9);

      await repository.rescheduleAppointment(appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', startTime: start);

      expect(client.lastParams?['p_duration_minutes'], isNull);
    });

    test('advanced: parses full RPC payload', () async {
      client.rpcResults['reschedule_appointment'] = {
        'success': true,
        'data': {
          'appointment_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'start_time': '2026-06-03T14:00:00.000Z',
          'end_time': '2026-06-03T14:45:00.000Z',
          'status': 'scheduled',
          'type': 'planned',
        },
      };

      final result = await repository.rescheduleAppointment(
        appointmentId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        startTime: DateTime.utc(2026, 6, 3, 14),
        durationMinutes: 45,
      );

      expect(result.startTime, DateTime.utc(2026, 6, 3, 14));
      expect(result.endTime, DateTime.utc(2026, 6, 3, 14, 45));
    });

    test('invalid state: SCHEDULE_CONFLICT surfaces from RPC', () async {
      client.rpcResults['reschedule_appointment'] = {
        'success': false,
        'error_code': 'SCHEDULE_CONFLICT',
        'error_message': 'Slot overlaps another appointment.',
      };

      expect(
        () => repository.rescheduleAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          startTime: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'SCHEDULE_CONFLICT')),
      );
    });

    test('invalid state: INVALID_INPUT when status is not scheduled', () async {
      client.rpcResults['reschedule_appointment'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Only scheduled planned appointments can be rescheduled.',
      };

      expect(
        () => repository.rescheduleAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          startTime: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('stupid usage: blank appointment id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.rescheduleAppointment(appointmentId: '  ', startTime: DateTime.utc(2026, 6, 1, 10)),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: duration below minimum rejected locally', () async {
      expect(
        () => repository.rescheduleAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          startTime: DateTime.utc(2026, 6, 1, 10),
          durationMinutes: 2,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['reschedule_appointment'] = {
        'success': true,
        'data': {'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'},
      };

      expect(
        () => repository.rescheduleAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          startTime: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: FORBIDDEN permission denial propagates', () async {
      client.rpcResults['reschedule_appointment'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Permission denied',
      };

      expect(
        () => repository.rescheduleAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          startTime: DateTime.utc(2026, 6, 1, 10),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });
}
