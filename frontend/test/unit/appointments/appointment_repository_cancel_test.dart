import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.cancelAppointment', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: forwards appointment id and optional reason', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      final status = await repository.cancelAppointment(appointmentId: appointmentId, reason: 'Patient called');

      expect(client.lastFunction, 'cancel_appointment');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(client.lastParams?['p_reason'], 'Patient called');
      expect(status, AppointmentStatus.cancelled);
    });

    test('advanced: omits reason when empty', () async {
      await repository.cancelAppointment(appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

      expect(client.lastParams?.containsKey('p_reason'), isFalse);
    });

    test('advanced: parses status from RPC payload', () async {
      client.rpcResults['cancel_appointment'] = {
        'success': true,
        'data': {'appointment_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'status': 'cancelled'},
      };

      final status = await repository.cancelAppointment(appointmentId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');

      expect(status, AppointmentStatus.cancelled);
    });

    test('invalid state: INVALID_INPUT surfaces from RPC', () async {
      client.rpcResults['cancel_appointment'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Only scheduled or checked-in appointments can be cancelled.',
      };

      expect(
        () => repository.cancelAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('stupid usage: reason over 2000 chars rejected locally', () async {
      expect(
        () => repository.cancelAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', reason: 'x' * 2001),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('edge case: blank appointment id rejected locally', () async {
      expect(
        () => repository.cancelAppointment(appointmentId: '   '),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('regression: FORBIDDEN surfaces from RPC', () async {
      client.rpcResults['cancel_appointment'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      expect(
        () => repository.cancelAppointment(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'FORBIDDEN')),
      );
    });
  });

  group('AppointmentRepository.markAppointmentNoShow', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: delegates to update_appointment_status with no_show', () async {
      const appointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      final status = await repository.markAppointmentNoShow(appointmentId: appointmentId);

      expect(client.lastFunction, 'update_appointment_status');
      expect(client.lastParams?['p_appointment_id'], appointmentId);
      expect(client.lastParams?['p_new_status'], 'no_show');
      expect(status, AppointmentStatus.noShow);
    });

    test('invalid state: INVALID_TRANSITION surfaces from RPC', () async {
      client.rpcResults['update_appointment_status'] = {
        'success': false,
        'error_code': 'INVALID_TRANSITION',
        'error_message': 'This status change is not allowed.',
      };

      expect(
        () => repository.markAppointmentNoShow(appointmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_TRANSITION')),
      );
    });
  });
}
