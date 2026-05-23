import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 widget test workspace — route builders ready for page widgets in Phase 3+.
void main() {
  group('Patient routes widget workspace (Phase 1)', () {
    test('route builders produce navigable paths for future GoRouter wiring', () {
      const patientId = 'test-patient-id';

      expect(AppRoutes.patients, isNotEmpty);
      expect(AppRoutes.patientDetail(patientId), '/patients/$patientId');
      expect(AppRoutes.patientEdit(patientId), '/patients/$patientId/edit');
      expect(AppRoutes.patientsNew, '/patients/new');
    });
  });
}
