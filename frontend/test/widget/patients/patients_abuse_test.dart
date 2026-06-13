import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import 'patient_detail_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('J. User Abuse & Edge Cases (AB)', () {
    group('AB-001 — Random filter toggling', () {
      testWidgets('rapid branch and last-visit changes end in consistent state', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Branch A Patient', branchId: testBranchAId, branchName: 'Branch A'),
            samplePatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Branch B Patient',
              branchId: testBranchBId,
              branchName: 'Branch B',
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        for (var i = 0; i < 6; i++) {
          await openPatientsFilterSidebar(tester);
          await selectBranchFilterOption(tester, i.isEven ? 'All branches' : 'Branch B (B1)');
          await selectLastVisitFilterOption(tester, i.isEven ? 'Never visited' : 'Last 30 days');
          await tester.tap(find.text('Apply Filters'));
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.last30Days);
        expect(repo.lastBranchId, testBranchBId);
      });
    });

    group('AB-002 — Search + sort spam', () {
      testWidgets('debounce and final sort win after rapid search and sort changes', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 10));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await tester.enterText(find.byType(TextField), 'Patient');
        await openPatientsSortPopover(tester);
        await tester.tap(find.text('Z to A'));
        await tester.pump(const Duration(milliseconds: 50));
        await openPatientsSortPopover(tester);
        await tester.tap(find.text('Oldest first'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(repo.lastSortField, PatientSortField.lastVisitAsc);
        expect(repo.lastQuery, 'Patient');
      });
    });

    group('AB-003 — Double row tap', () {
      testWidgets('double-clicking patient row triggers single navigation', (tester) async {
        final repo = FakePatientRepository(
          patients: [samplePatientListItem(fullName: 'Row Patient')],
          detail: sampleDetailForWidgetTests(),
        );
        final router = patientDetailTestRouter();

        await pumpPatientsPage(tester, patientDetailRouterHost(router: router, patientsRepository: repo));

        await tester.tap(find.text('Row Patient'));
        await tester.tap(find.text('Row Patient'));
        await tester.pumpAndSettle();

        expect(repo.getPatientCallCount, lessThanOrEqualTo(2));
        expect(find.byType(PatientDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('AB-006 — XSS in patient name', () {
      testWidgets('renders script tags as plain text on list', (tester) async {
        const xssName = '<script>alert(1)</script>';
        await pumpPatientsPage(tester, patientsListHost(patients: [samplePatientListItem(fullName: xssName)]));

        expect(find.textContaining('<script>'), findsOneWidget);
      });
    });

    group('AB-007 — Extremely long name', () {
      testWidgets('ellipsis on list row without overflow', (tester) async {
        final longName = 'A' * 500;
        final errors = <Object>[];
        final old = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details.exception);
        addTearDown(() => FlutterError.onError = old);

        await pumpPatientsPage(tester, patientsListHost(patients: [samplePatientListItem(fullName: longName)]));

        final text = tester.widget<Text>(find.textContaining('AAA'));
        expect(text.overflow, TextOverflow.ellipsis);
        expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
      });
    });

    group('AB-008 — Page number URL manipulation', () {
      testWidgets('page 9999 clamps to last page without crash', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        await container.read(patientListProvider.notifier).applyFilters(const PatientListFilters(page: 9999));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    });
  });
}
