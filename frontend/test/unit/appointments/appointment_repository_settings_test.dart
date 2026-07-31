import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.getAppointment', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: calls RPC with appointment id', () async {
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

    test('regression: null RPC payload throws StateError', () async {
      client.rpcResults['get_appointment'] = {'success': true, 'data': null};

      expect(
        () => repository.getAppointment(appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
        throwsA(isA<StateError>()),
      );
    });

    test('regression: malformed detail row throws StateError', () async {
      client.rpcResults['get_appointment'] = {
        'success': true,
        'data': {'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
      };

      expect(
        () => repository.getAppointment(appointmentId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AppointmentRepository.getSettings', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: calls RPC with branch id', () async {
      final settings = await repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444');

      expect(settings.defaultDurationMinutes, 20);
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

    test('advanced: maps all settings fields including working schedule', () async {
      client.rpcResults['get_appointment_settings'] = {
        'success': true,
        'data': {
          'default_duration_minutes': 25,
          'min_duration_minutes': 5,
          'max_duration_minutes': 180,
          'working_schedule': {
            'days': [
              {'day': 'monday', 'is_working_day': true, 'open_time': '08:00', 'close_time': '18:00'},
              {'day': 'sunday', 'is_working_day': false},
            ],
          },
        },
      };

      final settings = await repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444');

      expect(settings.defaultDurationMinutes, 25);
      expect(settings.minDurationMinutes, 5);
      expect(settings.maxDurationMinutes, 180);
      expect(settings.workingSchedule, isNotNull);
      expect(settings.workingSchedule!.days.first.openTime, '08:00');
      expect(settings.workingSchedule!.days.last.isWorkingDay, isFalse);
    });

    test('regression: null RPC payload throws StateError', () async {
      client.rpcResults['get_appointment_settings'] = {'success': true, 'data': null};

      expect(
        () => repository.getSettings(branchId: '44444444-4444-4444-8444-444444444444'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AppointmentRepository.setDefaultDuration', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('advanced: sends org-wide when branch omitted', () async {
      final minutes = await repository.setDefaultDuration(durationMinutes: 45);

      expect(minutes, 45);
      expect(client.lastFunction, 'set_appointment_default_duration');
      expect(client.lastParams?['p_duration_minutes'], 45);
      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('advanced: sends trimmed branch id when provided', () async {
      await repository.setDefaultDuration(
        durationMinutes: 30,
        branchId: ' 44444444-4444-4444-8444-444444444444 ',
      );

      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
    });

    test('edge case: blank branch id is omitted from RPC params', () async {
      await repository.setDefaultDuration(durationMinutes: 30, branchId: '   ');

      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('edge case: rejects duration below minimum before RPC', () async {
      expect(
        () => repository.setDefaultDuration(durationMinutes: 4),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: accepts exactly 5 minutes', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': 5},
      };

      final minutes = await repository.setDefaultDuration(durationMinutes: 5);

      expect(minutes, 5);
      expect(client.lastParams?['p_duration_minutes'], 5);
    });

    test('regression: throws when response omits saved minutes', () async {
      client.rpcResults['set_appointment_default_duration'] = {'success': true, 'data': <String, dynamic>{}};

      expect(() => repository.setDefaultDuration(durationMinutes: 45), throwsA(isA<StateError>()));
    });

    test('regression: throws when success has null duration field', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': null},
      };

      expect(() => repository.setDefaultDuration(durationMinutes: 45), throwsA(isA<StateError>()));
    });

    test('advanced: parses saved minutes from int response', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': 40},
      };

      expect(await repository.setDefaultDuration(durationMinutes: 40), 40);
    });

    test('advanced: parses saved minutes from num response', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': 35.0},
      };

      expect(await repository.setDefaultDuration(durationMinutes: 35), 35);
    });

    test('advanced: parses saved minutes from numeric string response', () async {
      client.rpcResults['set_appointment_default_duration'] = {
        'success': true,
        'data': {'default_duration_minutes': '50'},
      };

      expect(await repository.setDefaultDuration(durationMinutes: 50), 50);
    });
  });
}
