import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.updateAppointmentStatus', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: forwards appointment id and wire status', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      final update = await repository.updateAppointmentStatus(
        appointmentId: appointmentId,
        newStatus: AppointmentStatus.checkedIn,
      );

      expect(update.status, AppointmentStatus.checkedIn);
      expect(client.lastFunction, 'update_appointment_status');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(client.lastParams?['p_new_status'], 'checked_in');
    });

    test('advanced: returns parsed status from RPC payload', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': true,
        'data': {'appointment_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'status': 'in_progress'},
      };

      final update = await repository.updateAppointmentStatus(
        appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        newStatus: AppointmentStatus.inProgress,
      );

      expect(update.status, AppointmentStatus.inProgress);
    });

    test('invalid state: INVALID_TRANSITION surfaces from RPC', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': false,
        'error_code': 'INVALID_TRANSITION',
        'error_message': 'This status change is not allowed.',
      };

      expect(
        () => repository.updateAppointmentStatus(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          newStatus: AppointmentStatus.completed,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_TRANSITION')),
      );
    });

    test('stupid usage: blank appointment id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.updateAppointmentStatus(appointmentId: '  ', newStatus: AppointmentStatus.checkedIn),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: malformed success payload throws StateError', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': true,
        'data': {'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'status': 'not_a_status'},
      };

      expect(
        () => repository.updateAppointmentStatus(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          newStatus: AppointmentStatus.checkedIn,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('BUG-001: returns server timestamps from RPC payload', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': true,
        'data': {
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'status': 'checked_in',
          'updated_at': '2026-06-04T10:00:00.000Z',
          'checked_in_at': '2026-06-04T09:45:00.000Z',
          'in_progress_at': null,
        },
      };

      final update = await repository.updateAppointmentStatus(
        appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        newStatus: AppointmentStatus.checkedIn,
      );

      expect(update.checkedInAt, DateTime.utc(2026, 6, 4, 9, 45));
      expect(update.updatedAt, DateTime.utc(2026, 6, 4, 10));
      expect(update.inProgressAt, isNull);
    });

    test('regression: FORBIDDEN permission denial propagates', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Permission denied',
      };

      expect(
        () => repository.updateAppointmentStatus(
          appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          newStatus: AppointmentStatus.checkedIn,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });
}
