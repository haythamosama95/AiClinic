import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import 'patient_detail_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('I. Regression Testing (REG-007) — lab_staff read-only', () {
    testWidgets('patients list hides create action for lab_staff', (tester) async {
      await pumpPatientsPage(
        tester,
        patientsListHost(patients: samplePatientList(count: 2), permissions: RolePermissionSeed.labStaff),
      );

      expect(find.text('Patient 001'), findsOneWidget);
      expect(find.text('Add New Patient'), findsNothing);
    });

    testWidgets('patient detail hides edit and delete for lab_staff', (tester) async {
      await pumpPatientDetailPage(
        tester,
        patientDetailHost(detail: sampleDetailForWidgetTests(), permissions: RolePermissionSeed.labStaff),
      );
      await settlePatientDetail(tester);

      expect(find.byTooltip('Edit patient'), findsNothing);
      expect(find.byTooltip('Delete patient'), findsNothing);
    });
  });
}
