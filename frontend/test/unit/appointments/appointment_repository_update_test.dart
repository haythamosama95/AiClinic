import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.updateAppointment', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: forwards all params to update_appointment RPC', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final start = DateTime.utc(2026, 6, 4, 10);
      final end = DateTime.utc(2026, 6, 4, 10, 30);

      final result = await repository.updateAppointment(
        appointmentId: appointmentId,
        patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        doctorId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        branchId: '44444444-4444-4444-8444-444444444444',
        startTime: start,
        durationMinutes: 30,
        endTime: end,
        notes: 'Updated notes',
      );

      expect(result.status, AppointmentStatus.scheduled);
      expect(result.type, AppointmentType.planned);
      expect(client.lastFunction, 'update_appointment');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(client.lastParams?['p_patient_id'], 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
      expect(client.lastParams?['p_doctor_id'], 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_start_time'], start.toIso8601String());
      expect(client.lastParams?['p_duration_minutes'], 30);
      expect(client.lastParams?['p_end_time'], end.toIso8601String());
      expect(client.lastParams?['p_notes'], 'Updated notes');
    });

    test('BUG-004: blank doctor id is sent as null for unassignment', () async {
      await repository.updateAppointment(
        appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        doctorId: '   ',
        startTime: DateTime.utc(2026, 6, 4, 10),
      );

      expect(client.lastParams?['p_doctor_id'], isNull);
    });

    test('edge case: duration below minimum rejected before RPC', () async {
      expect(
        () => repository.updateAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          startTime: DateTime.utc(2026, 6, 4, 10),
          durationMinutes: 4,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: notes over 2000 chars rejected locally', () async {
      expect(
        () => repository.updateAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          startTime: DateTime.utc(2026, 6, 4, 10),
          notes: 'x' * 2001,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: notes exactly 2000 chars accepted', () async {
      final notes = 'x' * 2000;

      await repository.updateAppointment(
        appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        startTime: DateTime.utc(2026, 6, 4, 10),
        notes: notes,
      );

      expect(client.lastParams?['p_notes'], notes);
    });

    test('regression: null RPC payload throws StateError', () async {
      client.rpcResults['update_appointment'] = {'success': true, 'data': null};

      expect(
        () => repository.updateAppointment(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          patientId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          startTime: DateTime.utc(2026, 6, 4, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
