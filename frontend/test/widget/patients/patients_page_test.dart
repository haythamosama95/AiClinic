import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patients_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_active_filters_bar.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_list_controls.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_table.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_widget_test_harness.dart';

Finder _headerAddPatientButton() {
  final headerRow = find.ancestor(
    of: find.text('Patients'),
    matching: find.byType(Row),
  );
  return find.descendant(
    of: headerRow.first,
    matching: find.widgetWithText(AppButton, 'Add patient'),
  );
}

void main() {
  group('PatientsPage', () {
    testWidgets('trivial: PAT-PAGE-01 builds without exceptions in default success state', (tester) async {
      final notifier = SpyPatientListNotifier(buildPatientListState());

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Patient 001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('trivial: PAT-PAGE-02 shows loading skeleton while provider is loading', (tester) async {
      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(
          patientListOverride: patientListProvider.overrideWith(
            () => LoadingPatientListNotifier(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PatientTable), findsOneWidget);
      expect(find.byType(AppSkeleton), findsWidgets);
    });

    testWidgets('trivial: PAT-PAGE-03 shows first-run empty state with Add patient action', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: const [],
          totalCount: 0,
          filters: const PatientListFilters(pageSize: 10),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text('No patients yet'), findsOneWidget);
      expect(find.text('Add your first patient to start building records.'), findsOneWidget);
      expect(find.text('Add patient'), findsWidgets);
      expect(find.text('No patients match'), findsNothing);
      expect(find.byType(PatientListControls), findsNothing);
    });

    testWidgets('trivial: PAT-PAGE-04 shows no-match empty state distinct from first-run empty', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: const [],
          totalCount: 0,
          filters: const PatientListFilters(searchText: 'Sara', pageSize: 10),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text('No patients match'), findsOneWidget);
      expect(
        find.text('Try a different search term or clear your filters.'),
        findsOneWidget,
      );
      expect(find.text('Clear filters'), findsOneWidget);
      expect(find.text('No patients yet'), findsNothing);
      expect(find.text('Add your first patient to start building records.'), findsNothing);
    });

    testWidgets('trivial: PAT-PAGE-05 shows search-hint card when query is too short', (tester) async {
      const hint = 'Enter at least 3 characters to search by name.';
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: const [],
          totalCount: 0,
          filters: const PatientListFilters(searchText: 'ab', pageSize: 10),
          searchHint: hint,
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text(hint), findsOneWidget);
      expect(find.byType(PatientTable), findsNothing);
      expect(find.text('No patients match'), findsNothing);
      expect(find.text('No patients yet'), findsNothing);
    });

    testWidgets('trivial: PAT-PAGE-06 renders patient table rows and pagination in success state', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: samplePatientList(count: 2),
          totalCount: 2,
          filters: const PatientListFilters(pageSize: 10),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text('Patient 001'), findsOneWidget);
      expect(find.text('Patient 002'), findsOneWidget);
      expect(find.byType(PatientTable), findsOneWidget);
      expect(find.byType(AppPagination), findsOneWidget);
    });

    testWidgets('regression: PAT-PAGE-07 provider error leaves list in loading skeleton', (tester) async {
      const message = 'load failed';

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(
          patientListOverride: patientListProvider.overrideWith(
            () => ErrorPatientListNotifier(message),
          ),
        ),
      );
      await pumpPatientsFrames(tester);

      final container = patientsProviderContainer(tester);
      expect(container.read(patientListProvider), isA<AsyncError>());

      expect(find.byType(PatientTable), findsOneWidget);
      expect(find.byType(AppSkeleton), findsWidgets);
      expect(find.text('Patient 001'), findsNothing);
    });

    testWidgets('advanced: PAT-PAGE-08 reload and applyFilters fire on mount', (tester) async {
      final notifier = SpyPatientListNotifier(buildPatientListState());

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pump();

      expect(notifier.applyFiltersCallCount, 1);
      expect(notifier.lastAppliedFilters, const PatientListFilters(pageSize: 10));
      expect(notifier.reloadCallCount, 1);
    });

    testWidgets('advanced: PAT-PAGE-09 header Add patient opens the registration dialog', (tester) async {
      final notifier = SpyPatientListNotifier(buildPatientListState());

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      await tester.tap(_headerAddPatientButton());
      await tester.pumpAndSettle();

      expect(find.text('Register a new patient at your active branch.'), findsOneWidget);
      expect(find.text('Register patient'), findsOneWidget);
    });

    testWidgets('advanced: PAT-PAGE-10 Clear filters in no-match state resets filters', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: const [],
          totalCount: 12,
          filters: const PatientListFilters(searchText: 'Sara', pageSize: 10, page: 2),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      final callsBefore = notifier.applyFiltersCallCount;

      await tester.tap(find.text('Clear filters'));
      await pumpPatientsFrames(tester);

      expect(notifier.applyFiltersCallCount, callsBefore + 1);
      expect(notifier.lastAppliedFilters?.searchText, isEmpty);
      expect(notifier.lastAppliedFilters?.page, 1);
      expect(notifier.lastAppliedFilters?.pageSize, 10);
      expect(
        notifier.lastAppliedFilters?.lastVisitFilter,
        PatientLastVisitFilter.any,
      );
    });

    testWidgets('advanced: PAT-PAGE-11 pagination next page applies updated page filter', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          items: samplePatientList(count: 10),
          totalCount: 25,
          filters: const PatientListFilters(pageSize: 10, page: 1),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      final callsBefore = notifier.applyFiltersCallCount;

      await tester.tap(find.bySemanticsLabel('Next page'));
      await pumpPatientsFrames(tester);

      expect(notifier.applyFiltersCallCount, callsBefore + 1);
      expect(notifier.lastAppliedFilters?.page, 2);
      expect(notifier.lastAppliedFilters?.pageSize, 10);
    });

    testWidgets('advanced: PAT-PAGE-12 active filter chips appear when filters are active', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          filters: const PatientListFilters(
            searchText: 'Sara',
            lastVisitFilter: PatientLastVisitFilter.last30Days,
            pageSize: 10,
          ),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PatientActiveFiltersBar), findsOneWidget);
      expect(find.text('Search: Sara'), findsOneWidget);
      expect(find.text('Last visit: Last 30 days'), findsOneWidget);
    });

    testWidgets('trivial: PAT-PAGE-13 active filter chips are absent when filters are inactive', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          filters: const PatientListFilters(pageSize: 10),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filtered by'), findsNothing);
      expect(find.text('Clear all'), findsNothing);
    });

    testWidgets('advanced: PAT-PAGE-14 Clear all invokes notifier with default filters', (tester) async {
      final notifier = SpyPatientListNotifier(
        buildPatientListState(
          filters: const PatientListFilters(
            searchText: 'Sara',
            lastVisitFilter: PatientLastVisitFilter.last30Days,
            pageSize: 10,
            page: 2,
          ),
        ),
      );

      await pumpPatientsSurface(
        tester,
        child: const PatientsPage(),
        overrides: patientsProviderOverrides(listNotifier: notifier),
      );
      await tester.pumpAndSettle();

      final callsBefore = notifier.applyFiltersCallCount;

      await tester.tap(find.text('Clear all'));
      await pumpPatientsFrames(tester);

      expect(notifier.applyFiltersCallCount, callsBefore + 1);
      expect(notifier.lastAppliedFilters, const PatientListFilters(pageSize: 10));
    });
  });
}
