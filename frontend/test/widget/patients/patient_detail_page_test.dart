import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_error_state.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/edit_patient/edit_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/patient_test_support.dart';
import '../../helpers/breadcrumb_test_support.dart';
import 'patients_widget_test_harness.dart';

PatientDetail _detailWithMrn(String? mrn) {
  final base = samplePatientDetail(id: patientsTestPatientId);
  return PatientDetail(
    id: base.id,
    fullName: base.fullName,
    phone: base.phone,
    dateOfBirth: base.dateOfBirth,
    gender: base.gender,
    maritalStatus: base.maritalStatus,
    notes: base.notes,
    branchId: base.branchId,
    branchName: base.branchName,
    createdAt: base.createdAt,
    updatedAt: base.updatedAt,
    mrn: mrn,
  );
}

Future<void> _pumpPatientDetailPage(
  WidgetTester tester, {
  PatientDetailRouteExtra? extra,
  List<Override> overrides = const [],
  Set<String>? permissions,
}) async {
  await pumpPatientsSurface(
    tester,
    child: PatientDetailPage(
      patientId: patientsTestPatientId,
      extra: extra,
    ),
    overrides: overrides.isEmpty
        ? patientsProviderOverrides(patientId: patientsTestPatientId)
        : overrides,
    permissions: permissions,
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(
    tester.element(find.byType(PatientDetailPage)),
  )!;
}

RpcFailure _patientNotFoundFailure() {
  return RpcFailure(
    const RpcResult(
      success: false,
      errorCode: 'NOT_FOUND',
      errorMessage: 'Patient record is missing.',
    ),
  );
}

void main() {
  group('PatientDetailPage', () {
    testWidgets('trivial: builds in default success state with identity details', (tester) async {
      final detail = samplePatientDetail(
        id: patientsTestPatientId,
        fullName: 'Jordan Lee',
        phone: '+15551234567',
        branchName: 'Branch A',
      );

      await _pumpPatientDetailPage(
        tester,
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          patientDetail: detail,
        ),
      );

      final l10n = _l10n(tester);

      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.text('Jordan Lee'),
        ),
        findsOneWidget,
      );
      expect(find.text('+15551234567'), findsOneWidget);
      expect(find.text('Branch A'), findsOneWidget);
      expect(find.textContaining('Male'), findsOneWidget);
      expect(find.textContaining(l10n.dateOfBirthLabel), findsOneWidget);
      expect(find.text(l10n.visits), findsOneWidget);
      expect(find.text(l10n.documents), findsOneWidget);
      expect(find.text(l10n.billing), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('trivial: loading state shows skeleton affordances', (tester) async {
      await pumpPatientsSurface(
        tester,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const PatientDetailPage(patientId: patientsTestPatientId),
        ),
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          customPatientDetail: true,
          extraOverrides: [
            patientDetailProvider(patientsTestPatientId).overrideWith(
              (ref) => Completer<PatientDetail>().future,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(AppSkeleton), findsWidgets);
      expect(find.text('Test Patient'), findsNothing);
    });

    testWidgets('trivial: NOT_FOUND shows empty state and back action', (tester) async {
      await _pumpPatientDetailPage(
        tester,
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          detailError: _patientNotFoundFailure(),
        ),
      );

      final l10n = _l10n(tester);

      expect(find.text(l10n.patientNotFound), findsWidgets);
      expect(find.text(l10n.patientNotFoundDescription), findsOneWidget);
      expect(find.text(l10n.backToPatients), findsOneWidget);
      expect(find.byType(AppEmptyState), findsOneWidget);
    });

    testWidgets('advanced: error without preview shows retry and re-requests detail', (tester) async {
      var loadAttempts = 0;

      await pumpPatientsSurface(
        tester,
        child: const PatientDetailPage(patientId: patientsTestPatientId),
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          customPatientDetail: true,
          extraOverrides: [
            patientDetailProvider(patientsTestPatientId).overrideWith((ref) async {
              loadAttempts++;
              if (loadAttempts == 1) {
                throw StateError('Detail load failed');
              }
              return samplePatientDetail(id: patientsTestPatientId);
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Detail load failed'), findsOneWidget);
      expect(loadAttempts, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(loadAttempts, 2);
      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.text('Test Patient'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('edge case: error with preview keeps identity card and tab error', (tester) async {
      const previewName = 'Preview Patient';
      final preview = samplePatientListItem(
        id: patientsTestPatientId,
        fullName: previewName,
        phone: '+19998887777',
      );

      await _pumpPatientDetailPage(
        tester,
        extra: PatientDetailRouteExtra(preview: preview),
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          detailError: StateError('Detail load failed'),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppCard),
          matching: find.text(previewName),
        ),
        findsOneWidget,
      );
      expect(find.text('+19998887777'), findsOneWidget);
      expect(find.text('Detail load failed'), findsOneWidget);
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    group('action buttons', () {
      testWidgets('trivial: Edit patient is present when detail exists', (tester) async {
        await _pumpPatientDetailPage(tester);

        expect(find.text(_l10n(tester).editPatient), findsOneWidget);
      });

      testWidgets('trivial: Notes appears only when patient has non-empty notes', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientDetail: samplePatientDetail(
              id: patientsTestPatientId,
              notes: 'Allergy: penicillin',
            ),
          ),
        );

        expect(find.text(_l10n(tester).notesLabel), findsOneWidget);
      });

      testWidgets('trivial: Notes is absent when notes are empty', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientDetail: samplePatientDetail(
              id: patientsTestPatientId,
              notes: '   ',
            ),
          ),
        );

        expect(find.text(_l10n(tester).notesLabel), findsNothing);
      });

      testWidgets('advanced: Reassign MRN appears with permission and MRN', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          permissions: patientsWithReassignMrnPermission(),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            auth: patientsAuthSession(
              permissions: patientsWithReassignMrnPermission(),
            ),
            patientDetail: _detailWithMrn('MRN-000099'),
          ),
        );

        expect(find.text('Reassign MRN'), findsOneWidget);
      });

      testWidgets('advanced: Reassign MRN hidden without permission', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientDetail: _detailWithMrn('MRN-000099'),
          ),
        );

        expect(find.text('Reassign MRN'), findsNothing);
      });

      testWidgets('edge case: Reassign MRN hidden when patient has no MRN', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          permissions: patientsWithReassignMrnPermission(),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            auth: patientsAuthSession(
              permissions: patientsWithReassignMrnPermission(),
            ),
            patientDetail: _detailWithMrn(null),
          ),
        );

        expect(find.text('Reassign MRN'), findsNothing);
      });
    });

    group('interactions', () {
      testWidgets('trivial: Edit patient opens edit dialog', (tester) async {
        await _pumpPatientDetailPage(tester);

        final l10n = _l10n(tester);
        await tester.tap(find.text(l10n.editPatient));
        await tester.pumpAndSettle();

        expect(find.byType(EditPatientDialog), findsOneWidget);
        expect(find.text(l10n.editPatientDescription), findsOneWidget);
      });

      testWidgets('trivial: Notes opens dialog with note text', (tester) async {
        const notes = 'Follow up in two weeks.';

        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientDetail: samplePatientDetail(
              id: patientsTestPatientId,
              notes: notes,
            ),
          ),
        );

        final l10n = _l10n(tester);
        await tester.tap(find.text(l10n.notesLabel));
        await tester.pumpAndSettle();

        expect(find.text(l10n.clinicalNotesSectionTitle), findsOneWidget);
        expect(find.text(notes), findsOneWidget);
      });

      testWidgets('advanced: breadcrumb navigates back to patients list', (tester) async {
        final navigationLog = PatientsTestNavigationLog();

        await pumpPatientsRouter(
          tester,
          navigationLog: navigationLog,
          initialLocation: AppRoutes.patientDetail(patientsTestPatientId),
          home: const SizedBox(key: Key('patients_home')),
          patientDetailBuilder: (context, state) => PatientDetailPage(
            patientId: state.pathParameters['patientId']!,
            extra: PatientDetailRouteExtra.fromExtra(state.extra),
          ),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientDetail: samplePatientDetail(id: patientsTestPatientId),
            breadcrumbTrail: patientDetailTrail(
              patientId: patientsTestPatientId,
              patientName: 'Test Patient',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = _l10n(tester);
        await tester.tap(find.text(l10n.patients));
        await tester.pumpAndSettle();

        expect(navigationLog.visitedLocations, contains(AppRoutes.patients));
        expect(find.byKey(const Key('patients_home')), findsOneWidget);
      });

      testWidgets('breadcrumb patients segment uses localized label', (tester) async {
        await tester.binding.setSurfaceSize(patientsWideSurfaceSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          ProviderScope(
            overrides: patientsProviderOverrides(
              patientId: patientsTestPatientId,
              patientDetail: samplePatientDetail(
                id: patientsTestPatientId,
                fullName: 'Jordan Lee',
              ),
              breadcrumbTrail: patientDetailTrail(
                patientId: patientsTestPatientId,
                patientName: 'Jordan Lee',
              ),
            ),
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('ar'),
              home: PatientDetailPage(
                patientId: patientsTestPatientId,
                extra: PatientDetailRouteExtra(
                  breadcrumbTrail: patientDetailTrail(
                    patientId: patientsTestPatientId,
                    patientName: 'Jordan Lee',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('المرضى'), findsOneWidget);
      });
    });
  });
}
