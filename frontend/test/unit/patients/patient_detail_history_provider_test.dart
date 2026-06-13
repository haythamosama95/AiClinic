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
}
