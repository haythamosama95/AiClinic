import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('AppointmentRepository.listAppointments', () {
    late AppointmentRpcTestClient client;
    late AppointmentRepository repository;

    setUp(() {
      client = AppointmentRpcTestClient();
      repository = AppointmentRepository(client);
    });

    test('trivial: sends branch and date bounds', () async {
      final from = DateTime.utc(2026, 6, 1);
      final to = DateTime.utc(2026, 6, 2);

      await repository.listAppointments(branchId: '44444444-4444-4444-8444-444444444444', from: from, to: to);

      expect(client.lastFunction, 'list_appointments');
      expect(client.lastParams?['p_branch_id'], '44444444-4444-4444-8444-444444444444');
      expect(client.lastParams?['p_from'], from.toIso8601String());
      expect(client.lastParams?['p_to'], to.toIso8601String());
    });

    test('advanced: sends doctor, statuses, and patient filters', () async {
      await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 8),
        doctorId: '55555555-5555-4555-8555-555555555555',
        statuses: const [AppointmentStatus.scheduled, AppointmentStatus.checkedIn],
        patientId: '11111111-1111-4111-8111-111111111111',
      );

      expect(client.lastParams?['p_doctor_id'], '55555555-5555-4555-8555-555555555555');
      expect(client.lastParams?['p_statuses'], ['scheduled', 'checked_in']);
      expect(client.lastParams?['p_patient_id'], '11111111-1111-4111-8111-111111111111');
    });

    test('invalid state: inverted range throws INVALID_INPUT', () async {
      expect(
        () => repository.listAppointments(
          branchId: '44444444-4444-4444-8444-444444444444',
          from: DateTime.utc(2026, 6, 2),
          to: DateTime.utc(2026, 6, 1),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('invalid state: equal from and to throws INVALID_INPUT before RPC', () async {
      final instant = DateTime.utc(2026, 6, 1, 10);

      expect(
        () => repository.listAppointments(
          branchId: '44444444-4444-4444-8444-444444444444',
          from: instant,
          to: instant,
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('stupid usage: blank branch id throws INVALID_INPUT before RPC', () async {
      expect(
        () => repository.listAppointments(
          branchId: '  ',
          from: DateTime.utc(2026, 6, 1),
          to: DateTime.utc(2026, 6, 2),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.lastFunction, isNull);
    });

    test('edge case: non-List RPC payload returns empty list', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {'items': 'not-a-list'},
      };

      final items = await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(items, isEmpty);
    });

    test('edge case: plain Map rows are parsed', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            <String, dynamic>{
              'id': 'plain-map',
              'patient_id': 'p',
              'patient_name': 'Plain Map',
              'start_time': '2026-06-01T09:00:00Z',
              'end_time': '2026-06-01T09:30:00Z',
              'type': 'planned',
              'status': 'scheduled',
            },
          ],
        },
      };

      final items = await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(items, hasLength(1));
      expect(items.first.patientName, 'Plain Map');
    });

    test('edge case: malformed rows are skipped safely', () async {
      client.rpcResults['list_appointments'] = {
        'success': true,
        'data': {
          'items': [
            {
              'id': 'ok',
              'patient_id': 'p',
              'patient_name': 'Valid',
              'start_time': '2026-06-01T09:00:00Z',
              'end_time': '2026-06-01T09:30:00Z',
              'type': 'planned',
              'status': 'scheduled',
            },
            {'id': null},
          ],
        },
      };

      final items = await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(items, hasLength(1));
      expect(items.first.patientName, 'Valid');
    });

    test('REG-003 regression: branch-wide list omits p_patient_id', () async {
      await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
      );

      expect(client.lastParams?.containsKey('p_patient_id'), isFalse);
      expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
      expect(client.lastParams?.containsKey('p_statuses'), isFalse);
    });

    test('advanced: omits blank optional filters from RPC params', () async {
      await repository.listAppointments(
        branchId: '44444444-4444-4444-8444-444444444444',
        from: DateTime.utc(2026, 6, 1),
        to: DateTime.utc(2026, 6, 2),
        doctorId: '   ',
        statuses: const [],
        patientId: '  ',
      );

      expect(client.lastParams?.containsKey('p_doctor_id'), isFalse);
      expect(client.lastParams?.containsKey('p_statuses'), isFalse);
      expect(client.lastParams?.containsKey('p_patient_id'), isFalse);
    });
  });
}
