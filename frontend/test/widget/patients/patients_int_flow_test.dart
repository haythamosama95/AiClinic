import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import 'create_patient_test_support.dart';
import 'patient_detail_test_support.dart';
import 'patients_int_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('H. Integration & E2E (INT)', () {
    group('INT-001 — Register → detail → edit', () {
      testWidgets('creates patient, edits name on detail, and reflects update in list after back', (tester) async {
        const newPatientId = '33333333-3333-4333-8333-333333333333';
        final repo = StatefulFakePatientRepository(patients: samplePatientList(count: 2), createResult: newPatientId);
        final router = patientDetailTestRouter();

        await pumpPatientsPage(
          tester,
          patientDetailRouterHost(
            router: router,
            patientsRepository: repo,
            permissions: const {'patients.view', 'patients.create', 'patients.edit'},
          ),
        );
        final initialSearchCalls = repo.searchCallCount;

        await tester.tap(find.text('Add New Patient').first);
        await tester.pumpAndSettle();
        await fillValidCreatePatientForm(tester, name: 'Registered Patient');
        await tapRegisterPatient(tester);

        expect(find.text('Basic information'), findsOneWidget);
        expect(repo.createCallCount, 1);

        await tester.tap(find.byTooltip('Edit patient'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), 'Edited Patient');
        await tapUpdatePatient(tester);

        expect(find.text('Patient updated successfully.'), findsOneWidget);
        expect(repo.lastUpdateInput?.fullName, 'Edited Patient');

        await tapBackToPatientsList(tester);
        expect(repo.searchCallCount, greaterThan(initialSearchCalls));
        expect(find.text('Edited Patient'), findsOneWidget);
      });
    });

    group('INT-002 — Search → detail → back', () {
      testWidgets('preserves search text and results after detail navigation and back', (tester) async {
        final repo = FakePatientRepository(
          patients: samplePatientList(count: 5),
          detail: samplePatientDetail(id: '11111111-1111-4111-8111-000000000003', fullName: 'Patient 003'),
        );
        final router = patientDetailTestRouter();

        await pumpPatientsPage(
          tester,
          patientDetailRouterHost(
            router: router,
            patientsRepository: repo,
            permissions: const {'patients.view', 'patients.create', 'patients.edit'},
          ),
        );

        await enterPatientSearch(tester, 'Patient 003');
        expect(find.text('Patient 003'), findsWidgets);
        expect(find.text('Patient 001'), findsNothing);

        await tester.tap(find.text('Patient 003').last);
        await tester.pumpAndSettle();
        expect(find.byType(PatientDetailPage), findsOneWidget);

        await tapBackToPatientsList(tester);

        expect(find.text('Patient 003'), findsWidgets);
        expect(find.text('Patient 001'), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'Patient 003');
        expect(repo.lastQuery, 'Patient 003');
      });
    });

    group('INT-003 — Filter persists across navigation', () {
      testWidgets('keeps last-visit filter after navigating to detail and back', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Never Visited'),
            samplePatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Has Visit',
            ).copyWith(lastVisitAt: now),
          ],
          detail: samplePatientDetail(fullName: 'Never Visited'),
        );
        final router = patientDetailTestRouter();

        await pumpPatientsPage(
          tester,
          patientDetailRouterHost(router: router, patientsRepository: repo, permissions: const {'patients.view'}),
        );

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Never visited');
        await applyPatientsFilters(tester);
        expect(find.text('Never Visited'), findsOneWidget);
        expect(find.text('Has Visit'), findsNothing);

        await tapPatientRow(tester, 'Never Visited');
        await tapBackToPatientsList(tester);

        expect(find.text('Never Visited'), findsOneWidget);
        expect(find.text('Has Visit'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.never);
      });
    });

    group('INT-004 — Offline during list load', () {
      testWidgets('shows error on failed load and recovers after reload', (tester) async {
        final repo = FlakySearchPatientRepository(patients: samplePatientList(count: 3));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        expect(find.text('Unable to load patients'), findsOneWidget);

        final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        await container.read(patientListProvider.notifier).reload();
        await tester.pumpAndSettle();

        expect(find.text('Patient 001'), findsOneWidget);
        expect(find.text('Unable to load patients'), findsNothing);
      });
    });

    group('INT-007 — Refresh during page transition', () {
      testWidgets('deep-link to detail route loads without preview rect', (tester) async {
        final repo = FakePatientRepository(patients: [samplePatientListItem()], detail: sampleDetailForWidgetTests());
        final router = patientDetailTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId));

        await pumpPatientDetailPage(tester, patientDetailRouterHost(router: router, patientsRepository: repo));
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('re-pumping detail route mid-transition does not crash', (tester) async {
        final repo = FakePatientRepository(
          patients: [samplePatientListItem(fullName: 'Row Patient')],
          detail: sampleDetailForWidgetTests(),
        );
        final router = patientDetailTestRouter();

        await pumpPatientDetailPage(tester, patientDetailRouterHost(router: router, patientsRepository: repo));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Row Patient'));
        await tester.pump(const Duration(milliseconds: 150));

        await pumpPatientDetailPage(
          tester,
          patientDetailRouterHost(
            router: patientDetailTestRouter(initialLocation: AppRoutes.patientDetail(patientDetailTestId)),
            patientsRepository: repo,
          ),
        );
        await settlePatientDetail(tester);

        expect(find.text('Basic information'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
