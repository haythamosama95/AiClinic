import 'package:clock/clock.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('B. Patient Detail — Functional (PD-F) history providers', () {
    test('PD-F-006: past visits sorted desc by visit date', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visits': {
            'success': true,
            'data': {
              'items': [
                {
                  'id': '11111111-1111-4111-8111-111111111111',
                  'visit_date': '2026-04-10T14:30:00.000Z',
                  'doctor_name': 'Dr Older',
                  'status': 'completed',
                  'branch_name': 'Main',
                },
                {
                  'id': '22222222-2222-4222-8222-222222222222',
                  'visit_date': '2026-05-20T09:00:00.000Z',
                  'doctor_name': 'Dr Newer',
                  'status': 'completed',
                  'branch_name': 'Main',
                },
              ],
              'total_count': 2,
              'limit': 100,
              'offset': 0,
            },
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      const patientId = '11111111-1111-4111-8111-111111111111';
      final visits = await container.read(patientPastVisitsProvider(patientId).future);

      expect(visits, hasLength(2));
      expect(visits.first.doctorName, 'Dr Newer');
      expect(visits.last.doctorName, 'Dr Older');
      expect(visits.first.visitDate.isAfter(visits.last.visitDate), isTrue);
    });

    test('PD-F-007: upcoming appointments are patient-scoped and sorted asc', () async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {
              'items': [
                {
                  'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  'patient_id': '11111111-1111-4111-8111-111111111111',
                  'patient_name': 'Sara Ali',
                  'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                  'doctor_name': 'Dr Later',
                  'start_time': '2026-09-15T14:00:00.000Z',
                  'end_time': '2026-09-15T14:30:00.000Z',
                  'type': 'planned',
                  'status': 'scheduled',
                },
                {
                  'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                  'patient_id': '11111111-1111-4111-8111-111111111111',
                  'patient_name': 'Sara Ali',
                  'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                  'doctor_name': 'Dr Future',
                  'start_time': '2026-08-01T09:00:00.000Z',
                  'end_time': '2026-08-01T09:30:00.000Z',
                  'type': 'planned',
                  'status': 'confirmed',
                },
              ],
            },
          },
        },
      );
      final container = ProviderContainer(
        overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
      );
      addTearDown(container.dispose);

      const patientId = '11111111-1111-4111-8111-111111111111';
      const branchId = '44444444-4444-4444-8444-444444444444';

      final appointments = await container.read(
        patientUpcomingAppointmentsProvider(
          const PatientDetailHistoryQuery(patientId: patientId, branchId: branchId),
        ).future,
      );

      expect(appointments, hasLength(2));
      expect(appointments.first.doctorDisplayName, 'Dr Future');
      expect(appointments.last.doctorDisplayName, 'Dr Later');
      expect(client.lastParams?['p_patient_id'], patientId);
      expect(client.lastParams?['p_branch_id'], branchId);
    });

    test('M1: upcoming appointments requests patient-scoped list_appointments', () async {
      final client = AppointmentRpcTestClient();
      final container = ProviderContainer(
        overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
      );
      addTearDown(container.dispose);

      const patientId = '11111111-1111-4111-8111-111111111111';
      const branchId = '44444444-4444-4444-8444-444444444444';

      await container.read(
        patientUpcomingAppointmentsProvider(
          const PatientDetailHistoryQuery(patientId: patientId, branchId: branchId),
        ).future,
      );

      expect(client.lastFunction, 'list_appointments');
      expect(client.lastParams?['p_branch_id'], branchId);
      expect(client.lastParams?['p_patient_id'], patientId);
    });
  });

  group('PatientDetailHistoryTabNotifier', () {
    test('starts on past tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(patientDetailHistoryTabProvider('patient-a')),
        PatientDetailHistoryTab.past,
      );
    });

    test('select switches to upcoming', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(patientDetailHistoryTabProvider('patient-a').notifier)
          .select(PatientDetailHistoryTab.upcoming);

      expect(
        container.read(patientDetailHistoryTabProvider('patient-a')),
        PatientDetailHistoryTab.upcoming,
      );
    });

    test('family isolates tab state per patient id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(patientDetailHistoryTabProvider('patient-a').notifier)
          .select(PatientDetailHistoryTab.upcoming);

      expect(
        container.read(patientDetailHistoryTabProvider('patient-a')),
        PatientDetailHistoryTab.upcoming,
      );
      expect(
        container.read(patientDetailHistoryTabProvider('patient-b')),
        PatientDetailHistoryTab.past,
      );
    });
  });

  group('PatientDetailHistoryQuery', () {
    test('equal instances compare equal and share hashCode', () {
      const left = PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-a');
      const right = PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-a');

      expect(left, equals(right));
      expect(left.hashCode, right.hashCode);
    });

    test('differing branchId is not equal', () {
      const left = PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-a');
      const right = PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-b');

      expect(left == right, isFalse);
      expect(left.hashCode == right.hashCode, isFalse);
    });
  });

  group('Patient detail history provider edge cases', () {
    test('patientPastVisitsProvider returns empty list when RPC has no items', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visits': {
            'success': true,
            'data': {'items': [], 'total_count': 0, 'limit': 100, 'offset': 0},
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      final visits = await container.read(patientPastVisitsProvider('patient-a').future);

      expect(visits, isEmpty);
    });

    test('patientPastVisitsProvider propagates repository errors', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visits': {
            'success': false,
            'error_code': 'INTERNAL',
            'error_message': 'visit list failed',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(patientPastVisitsProvider('patient-a').future),
        throwsA(anything),
      );
    });

    test('patientUpcomingAppointmentsProvider returns empty list when RPC has no items', () async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': true,
            'data': {'items': []},
          },
        },
      );
      final container = ProviderContainer(
        overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
      );
      addTearDown(container.dispose);

      final appointments = await container.read(
        patientUpcomingAppointmentsProvider(
          const PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-a'),
        ).future,
      );

      expect(appointments, isEmpty);
    });

    test('patientUpcomingAppointmentsProvider propagates repository errors', () async {
      final client = AppointmentRpcTestClient(
        rpcResults: {
          'list_appointments': {
            'success': false,
            'error_code': 'INTERNAL',
            'error_message': 'appointment list failed',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(
          patientUpcomingAppointmentsProvider(
            const PatientDetailHistoryQuery(patientId: 'patient-a', branchId: 'branch-a'),
          ).future,
        ),
        throwsA(anything),
      );
    });

    test('patientUpcomingAppointmentsProvider forwards status filters and date window', () async {
      final fixedNow = DateTime.utc(2026, 7, 1, 12, 30);
      final client = AppointmentRpcTestClient();
      final container = ProviderContainer(
        overrides: [appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(client))],
      );
      addTearDown(container.dispose);

      await withClock(Clock.fixed(fixedNow), () async {
        await container.read(
          patientUpcomingAppointmentsProvider(
            const PatientDetailHistoryQuery(
              patientId: '11111111-1111-4111-8111-111111111111',
              branchId: '44444444-4444-4444-8444-444444444444',
            ),
          ).future,
        );
      });

      expect(client.lastParams?['p_statuses'], [
        'scheduled',
        'confirmed',
        'checked_in',
        'in_progress',
      ]);
      expect(client.lastParams?['p_from'], fixedNow.toUtc().toIso8601String());
      expect(
        client.lastParams?['p_to'],
        fixedNow.toUtc().add(const Duration(days: 365)).toIso8601String(),
      );
    });

    test('patientVisitDocumentsProvider returns empty list when RPC has no items', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visit_attachments': {
            'success': true,
            'data': {'items': [], 'total_count': 0, 'limit': 100, 'offset': 0},
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      final documents = await container.read(patientVisitDocumentsProvider('patient-a').future);

      expect(documents, isEmpty);
    });

    test('patientVisitDocumentsProvider propagates repository errors', () async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visit_attachments': {
            'success': false,
            'error_code': 'INTERNAL',
            'error_message': 'attachments failed',
          },
        },
      );
      final container = ProviderContainer(
        overrides: [visitRepositoryProvider.overrideWith((ref) => VisitRepository(client))],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(patientVisitDocumentsProvider('patient-a').future),
        throwsA(anything),
      );
    });
  });
}
