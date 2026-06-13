import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_page.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import 'create_patient_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('A. Patients List — Functional (PL-F)', () {
    group('PL-F-001 — Load', () {
      testWidgets('renders table rows and pagination footer total', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 3));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        expect(find.text('Patient 001'), findsOneWidget);
        expect(find.text('Patient 002'), findsOneWidget);
        expect(find.textContaining('Showing 1–3 of 3'), findsOneWidget);
        expect(find.byType(PatientsTable), findsOneWidget);
      });
    });

    group('PL-F-002 — Empty clinic', () {
      testWidgets('shows no patients yet empty state with add CTA when create allowed', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: const []));

        expect(find.text('No patients yet'), findsOneWidget);
        expect(find.text('Add New Patient'), findsWidgets);
      });

      testWidgets('hides add CTA without patients.create permission', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: const [], permissions: const {'patients.view'}));

        expect(find.text('No patients yet'), findsOneWidget);
        expect(find.text('Add New Patient'), findsNothing);
      });
    });

    group('PL-F-003 — Permission denied', () {
      testWidgets('shows denial message without calling search RPC', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 2));
        await pumpPatientsPage(tester, patientsListHost(repository: repo, permissions: const {'patients.create'}));

        expect(find.textContaining('do not have permission'), findsOneWidget);
        expect(find.text('Patient 001'), findsNothing);
        expect(repo.searchCallCount, 0);
      });
    });

    group('PL-F-004 — Search name happy', () {
      testWidgets('debounced name search shows only matching patients', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Alice Anderson'),
            samplePatientListItem(id: '22222222-2222-4222-8222-222222222222', fullName: 'Bob Baker'),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await enterPatientSearch(tester, 'Ali');

        expect(find.text('Alice Anderson'), findsOneWidget);
        expect(find.text('Bob Baker'), findsNothing);
        expect(repo.lastQuery, 'Ali');
      });
    });

    group('PL-F-005 — Search phone happy', () {
      testWidgets('phone prefix search returns matching patients', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Phone Patient', phone: '201234567890'),
            samplePatientListItem(id: '22222222-2222-4222-8222-222222222222', fullName: 'Other', phone: '309998887766'),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await enterPatientSearch(tester, '2012345');

        expect(find.text('Phone Patient'), findsOneWidget);
        expect(find.text('Other'), findsNothing);
      });
    });

    group('PL-F-006 — Search too short name', () {
      testWidgets('shows inline hint without RPC for two-letter name query', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 2));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));
        final callsBefore = repo.searchCallCount;

        await enterPatientSearch(tester, 'Al');

        expect(find.textContaining('at least 3 characters'), findsOneWidget);
        expect(find.text('Patient 001'), findsNothing);
        expect(repo.searchCallCount, callsBefore);
      });
    });

    group('PL-F-007 — Search too short phone', () {
      testWidgets('shows validation hint for single digit phone query', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 1));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await enterPatientSearch(tester, '2');

        expect(find.textContaining('at least 2 digits'), findsOneWidget);
        expect(repo.lastQuery, isNull);
      });
    });

    group('PL-F-008 — Search no match', () {
      testWidgets('shows no matches empty state', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 2));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await enterPatientSearch(tester, 'ZZZZNOTFOUND');

        expect(find.text('No patients match your search criteria'), findsOneWidget);
      });
    });

    group('PL-F-009 — Clear search', () {
      testWidgets('restores full list and resets to page 1', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await enterPatientSearch(tester, 'Patient 001');
        expect(find.text('Patient 002'), findsNothing);

        await enterPatientSearch(tester, '');
        expect(find.text('Patient 002'), findsOneWidget);
        expect(find.textContaining('Showing 1–20 of 25'), findsOneWidget);
      });
    });

    group('PL-F-010 — Pagination next', () {
      testWidgets('loads next page with updated footer summary', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Showing 21–25 of 25'), findsOneWidget);
        expect(find.text('Patient 021'), findsOneWidget);
        expect(repo.searchOffsets, contains(20));
      });
    });

    group('PL-F-011 — Pagination prev', () {
      testWidgets('returns to first page with correct offset', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Previous page'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Showing 1–20 of 25'), findsOneWidget);
        expect(find.text('Patient 001'), findsOneWidget);
        expect(repo.searchOffsets.last, 0);
      });
    });

    group('PL-F-012 — Pagination disabled at bounds', () {
      testWidgets('disables prev and next on single page', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 5));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        expect(patientsPaginationButton(tester, 'Previous page').onPressed, isNull);
        expect(patientsPaginationButton(tester, 'Next page').onPressed, isNull);
        expect(find.text('1 / 1'), findsOneWidget);
      });
    });

    group('PL-F-013 — Rapid pagination', () {
      testWidgets('handles rapid next clicks without crash', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 100));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        for (var i = 0; i < 5; i++) {
          final next = patientsPaginationButton(tester, 'Next page').onPressed;
          if (next != null) {
            await tester.tap(find.byTooltip('Next page'));
          }
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.textContaining(' of 100'), findsOneWidget);
        expect(repo.searchCallCount, greaterThan(1));
        expect(repo.searchOffsets.last, greaterThan(0));
      });
    });

    group('PL-F-014 — Branch filter current', () {
      testWidgets('shows only active branch patients', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            ...samplePatientList(count: 2, branchId: testBranchAId, branchName: 'Branch A', namePrefix: 'Alpha'),
            ...samplePatientList(count: 2, branchId: testBranchBId, branchName: 'Branch B', namePrefix: 'Beta'),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo, activeBranchId: testBranchAId));

        expect(find.text('Alpha 001'), findsOneWidget);
        expect(find.text('Beta 001'), findsNothing);
        expect(repo.lastScope, PatientListScope.thisBranch);
        expect(repo.lastBranchId, testBranchAId);
      });
    });

    group('PL-F-015 — Branch filter all', () {
      testWidgets('shows org-wide patients with organization scope', (tester) async {
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

        await openPatientsFilterSidebar(tester);
        await selectBranchFilterOption(tester, 'All branches');
        await applyPatientsFilters(tester);

        expect(find.text('Branch A Patient'), findsOneWidget);
        expect(find.text('Branch B Patient'), findsOneWidget);
        expect(repo.lastScope, PatientListScope.allBranches);
        expect(repo.lastBranchId, isNull);
      });
    });

    group('PL-F-016 — Branch filter specific', () {
      testWidgets('shows only selected branch patients', (tester) async {
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

        await openPatientsFilterSidebar(tester);
        await selectBranchFilterOption(tester, 'Branch B (B1)');
        await applyPatientsFilters(tester);

        expect(find.text('Branch B Patient'), findsOneWidget);
        expect(find.text('Branch A Patient'), findsNothing);
        expect(repo.lastBranchId, testBranchBId);
      });
    });

    group('PL-F-017 — Last visit never', () {
      testWidgets('filters to patients without completed visits', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Never Visited'),
            samplePatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Has Visit',
            ).copyWith(lastVisitAt: now.subtract(const Duration(days: 5))),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Never visited');
        await applyPatientsFilters(tester);

        expect(find.text('Never Visited'), findsOneWidget);
        expect(find.text('Has Visit'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.never);
        expect(find.textContaining('Showing 1–1 of 1'), findsOneWidget);
      });
    });

    group('PL-F-018 — Last visit 30 days', () {
      testWidgets('includes patients visited within 30 days', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            PatientListItem(
              id: '11111111-1111-4111-8111-111111111111',
              fullName: 'Recent Visitor',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 10)),
            ),
            PatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Old Visitor',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 60)),
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Last 30 days');
        await applyPatientsFilters(tester);

        expect(find.text('Recent Visitor'), findsOneWidget);
        expect(find.text('Old Visitor'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.last30Days);
      });
    });

    group('PL-F-019 — Last visit 90 days', () {
      testWidgets('includes patients visited within 90 days', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            PatientListItem(
              id: '11111111-1111-4111-8111-111111111111',
              fullName: 'Within 90',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 80)),
            ),
            PatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Over 90',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 100)),
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Last 90 days');
        await applyPatientsFilters(tester);

        expect(find.text('Within 90'), findsOneWidget);
        expect(find.text('Over 90'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.last90Days);
      });
    });

    group('PL-F-020 — Last visit over 90 days', () {
      testWidgets('includes patients visited more than 90 days ago', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            PatientListItem(
              id: '11111111-1111-4111-8111-111111111111',
              fullName: 'Ancient Visitor',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 100)),
            ),
            PatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Recent Visitor',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 10)),
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Over 90 days ago');
        await applyPatientsFilters(tester);

        expect(find.text('Ancient Visitor'), findsOneWidget);
        expect(find.text('Recent Visitor'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.over90Days);
      });
    });

    group('PL-F-021 — Sort name desc', () {
      testWidgets('orders patients Z–A across pages', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsSortPopover(tester);
        await tester.tap(find.text('Z to A'));
        await tester.pumpAndSettle();

        expect(find.text('Patient 025'), findsOneWidget);
        expect(repo.lastSortField, PatientSortField.nameDesc);

        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();

        expect(find.text('Patient 005'), findsOneWidget);
        expect(find.text('Patient 025'), findsNothing);
      });
    });

    group('PL-F-022 — Sort last visit asc', () {
      testWidgets('places null last visits last with oldest visit first', (tester) async {
        final now = DateTime.now().toUtc();
        final repo = FakePatientRepository(
          patients: [
            PatientListItem(
              id: '11111111-1111-4111-8111-111111111111',
              fullName: 'No Visit',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
            ),
            PatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Old Visit',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 200)),
            ),
            PatientListItem(
              id: '33333333-3333-4333-8333-333333333333',
              fullName: 'New Visit',
              registeringBranchId: testBranchAId,
              registeringBranchName: 'Branch A',
              lastVisitAt: now.subtract(const Duration(days: 10)),
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsSortPopover(tester);
        await tester.tap(find.text('Oldest first'));
        await tester.pumpAndSettle();

        expect(find.text('Old Visit'), findsOneWidget);
        expect(repo.lastSortField, PatientSortField.lastVisitAsc);

        final oldY = tester.getTopLeft(find.text('Old Visit')).dy;
        final newY = tester.getTopLeft(find.text('New Visit')).dy;
        final noY = tester.getTopLeft(find.text('No Visit')).dy;
        expect(oldY, lessThan(newY));
        expect(newY, lessThan(noY));
      });
    });

    group('PL-F-023 — Filter + sort combo', () {
      testWidgets('applies never filter with name ascending sort', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(fullName: 'Zara Zero'),
            samplePatientListItem(id: '22222222-2222-4222-8222-222222222222', fullName: 'Adam Alpha'),
            samplePatientListItem(
              id: '33333333-3333-4333-8333-333333333333',
              fullName: 'Visited',
            ).copyWith(lastVisitAt: DateTime.now().toUtc()),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Never visited');
        await applyPatientsFilters(tester);

        await openPatientsSortPopover(tester);
        await tester.tap(find.text('A to Z'));
        await tester.pumpAndSettle();

        expect(find.text('Adam Alpha'), findsOneWidget);
        expect(find.text('Zara Zero'), findsOneWidget);
        expect(find.text('Visited'), findsNothing);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.never);
        expect(repo.lastSortField, PatientSortField.nameAsc);
        expect(find.textContaining('Showing 1–2 of 2'), findsOneWidget);
      });
    });

    group('PL-F-024 — Filter badge count', () {
      testWidgets('shows badge 2 when branch and last visit filters active', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 1)));

        await openPatientsFilterSidebar(tester);
        await selectBranchFilterOption(tester, 'All branches');
        await selectLastVisitFilterOption(tester, 'Never visited');
        await applyPatientsFilters(tester);

        expect(find.text('2'), findsOneWidget);
      });
    });

    group('PL-F-025 — Clear all filters', () {
      testWidgets('resets filters and reloads full list', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            samplePatientListItem(
              fullName: 'Branch A Patient',
              branchId: testBranchAId,
              branchName: 'Branch A',
            ).copyWith(lastVisitAt: DateTime.now().toUtc()),
            samplePatientListItem(
              id: '22222222-2222-4222-8222-222222222222',
              fullName: 'Branch B Patient',
              branchId: testBranchBId,
              branchName: 'Branch B',
            ),
          ],
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo, activeBranchId: testBranchAId));

        await openPatientsFilterSidebar(tester);
        await selectLastVisitFilterOption(tester, 'Never visited');
        await applyPatientsFilters(tester);
        expect(find.text('Branch A Patient'), findsNothing);

        await openPatientsFilterSidebar(tester);
        await clearPatientsFilters(tester);

        expect(find.text('Branch A Patient'), findsOneWidget);
        expect(repo.lastLastVisitFilter, PatientLastVisitFilter.any);
      });
    });

    group('PL-F-026 — Assigned doctor absent', () {
      testWidgets('filter sidebar has no assigned doctor control', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 1)));

        await openPatientsFilterSidebar(tester);

        expect(find.text('Assigned Doctor'), findsNothing);
        expect(find.byType(AppFilterSelect<PatientLastVisitFilter>), findsOneWidget);
      });
    });

    group('PL-F-027 — Branch switch reload', () {
      testWidgets('reloads list when shell active branch changes', (tester) async {
        final repo = FakePatientRepository(
          patients: [
            ...samplePatientList(count: 1, branchId: testBranchAId, branchName: 'Branch A', namePrefix: 'Alpha'),
            ...samplePatientList(count: 1, branchId: testBranchBId, branchName: 'Branch B', namePrefix: 'Beta'),
          ],
        );
        final auth = SwitchablePatientsListAuthNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(branchIds: [testBranchAId, testBranchBId], activeBranchId: testBranchAId),
          ),
        );

        await pumpPatientsPage(tester, patientsListHost(repository: repo, authNotifier: auth));
        expect(find.text('Alpha 001'), findsOneWidget);
        expect(repo.searchCallCount, 1);
        expect(repo.lastBranchId, testBranchAId);

        auth.setActiveBranch(testBranchBId);
        await tester.pumpAndSettle();

        expect(find.text('Beta 001'), findsOneWidget);
        expect(find.text('Alpha 001'), findsNothing);
        expect(repo.searchCallCount, 2);
        expect(repo.lastBranchId, testBranchBId);
      });
    });

    group('PL-F-028 — Loading skeleton', () {
      testWidgets('shows skeleton on initial load while toolbar stays interactive', (tester) async {
        final completer = Completer<void>();
        final repo = _CompletablePatientRepository(patients: samplePatientList(count: 3), firstSearchGate: completer);
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(patientsListHost(repository: repo));
        await tester.pump();

        expect(find.byType(PatientsTableSkeleton), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Add New Patient'), findsOneWidget);

        completer.complete();
        await tester.pumpAndSettle();
      });
    });

    group('PL-F-029 — Error state', () {
      testWidgets('shows error empty state when search RPC fails', (tester) async {
        final repo = FakePatientRepository(
          patients: samplePatientList(count: 2),
          searchException: StateError('Network failure'),
        );
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        expect(find.text('Unable to load patients'), findsOneWidget);
        expect(find.textContaining('Network failure'), findsOneWidget);
      });
    });

    group('PL-F-030 — skipLoadingOnReload', () {
      testWidgets('does not flash skeleton when changing page', (tester) async {
        final repo = FakePatientRepository(patients: samplePatientList(count: 25));
        await pumpPatientsPage(tester, patientsListHost(repository: repo));

        expect(find.byType(PatientsTableSkeleton), findsNothing);

        await tester.tap(find.byTooltip('Next page'));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(PatientsTableSkeleton), findsNothing);
        expect(find.byType(PatientsTable), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.text('Patient 021'), findsOneWidget);
      });
    });
  });

  group('C. Create / Edit Patient — List page (CP-F)', () {
    group('CP-F-001 — Create / Happy path', () {
      testWidgets('registers from toolbar, invalidates list, and navigates to detail', (tester) async {
        const newPatientId = '33333333-3333-4333-8333-333333333333';
        final detail = samplePatientDetail(id: newPatientId, fullName: 'Registered Patient');
        final repo = FakePatientRepository(
          patients: samplePatientList(count: 2),
          detail: detail,
          createResult: newPatientId,
        );

        await pumpPatientsPage(tester, patientsListRouterHost(repository: repo));
        expect(repo.searchCallCount, 1);

        await tester.tap(find.text('Add New Patient').first);
        await tester.pumpAndSettle();

        await fillValidCreatePatientForm(tester, name: 'Registered Patient');
        await tapRegisterPatient(tester);

        expect(find.text('Patient registered successfully.'), findsOneWidget);
        expect(find.text('Basic information'), findsOneWidget);
        expect(repo.createCallCount, 1);

        await tester.tap(find.byTooltip('Back to patients'));
        await tester.pumpAndSettle();

        expect(repo.searchCallCount, greaterThan(1));
      });
    });

    group('CP-F-002 — Create / No permission', () {
      testWidgets('hides add patient action without patients.create', (tester) async {
        await pumpPatientsPage(
          tester,
          patientsListHost(patients: samplePatientList(count: 2), permissions: const {'patients.view'}),
        );

        expect(find.text('Add New Patient'), findsNothing);
      });
    });
  });
}

class _CompletablePatientRepository extends FakePatientRepository {
  _CompletablePatientRepository({required super.patients, required this.firstSearchGate});

  final Completer<void> firstSearchGate;
  var _released = false;

  @override
  Future<PatientSearchPage> searchPatients({
    String? query,
    required PatientListScope scope,
    String? branchId,
    int limit = 25,
    int offset = 0,
    PatientLastVisitFilter lastVisitFilter = PatientLastVisitFilter.any,
    PatientSortField sortField = PatientSortField.nameAsc,
  }) async {
    if (!_released) {
      await firstSearchGate.future;
      _released = true;
    }
    return super.searchPatients(
      query: query,
      scope: scope,
      branchId: branchId,
      limit: limit,
      offset: offset,
      lastVisitFilter: lastVisitFilter,
      sortField: sortField,
    );
  }
}
