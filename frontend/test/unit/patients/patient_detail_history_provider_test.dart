import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('Patient detail history providers medium-severity regressions', () {
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
