import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patients_page.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_widget_test_harness.dart';

void main() {
  group('PatientsPage navigation', () {
    testWidgets('advanced: PAT-NAV-01 tapping a patient row navigates to patient detail', (tester) async {
      const patientId = patientsTestPatientId;
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: [
            samplePatientListItem(
              id: patientId,
              fullName: 'Nav Patient',
            ),
          ],
          filters: const PatientListFilters(pageSize: 10),
        ),
      );

      final bundle = await pumpPatientsRouter(
        tester,
        home: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(bundle.navigationLog.visitedLocations, contains(AppRoutes.patients));

      await tester.tap(find.text('Nav Patient'));
      await tester.pumpAndSettle();

      expect(
        find.text('stub:patient-$patientId'),
        findsOneWidget,
      );
      expect(
        bundle.navigationLog.visitedLocations,
        contains(AppRoutes.patientDetail(patientId)),
      );
    });

    testWidgets('edge case: PAT-NAV-02 tapping non-row content does not navigate away', (tester) async {
      const patientId = patientsTestPatientId;
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: [
            samplePatientListItem(
              id: patientId,
              fullName: 'Nav Patient',
            ),
          ],
          filters: const PatientListFilters(pageSize: 10),
        ),
      );

      final bundle = await pumpPatientsRouter(
        tester,
        home: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      final locationsBefore = List<String>.from(bundle.navigationLog.visitedLocations);

      await tester.tap(
        find.text('Manage patient records, profiles, and medical history.'),
      );
      await tester.pumpAndSettle();

      expect(bundle.navigationLog.visitedLocations, locationsBefore);
      expect(find.text('stub:patient-$patientId'), findsNothing);
      expect(find.text('Nav Patient'), findsOneWidget);
    });
  });
}
