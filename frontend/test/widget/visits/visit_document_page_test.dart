import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_rich_text_editor.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_document_page.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_content.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_rail.dart';

import 'visit_widget_test_harness.dart';

const _patientName = 'Jane Doe';
const _appointmentBreadcrumbLabel = 'Jane Doe · May 31, 2026';

PatientDetail _testPatient() {
  return PatientDetail(
    id: encounterTestPatientId,
    fullName: _patientName,
    dateOfBirth: DateTime.utc(1990, 1, 15),
    branchId: encounterTestBranchId,
    branchName: 'Main',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

AppointmentDetail _testAppointment() {
  return AppointmentDetail(
    id: encounterTestAppointmentId,
    branchId: encounterTestBranchId,
    patientId: encounterTestPatientId,
    patientName: _patientName,
    doctorId: encounterTestDoctorId,
    doctorName: 'Dr Test',
    startTime: DateTime.utc(2026, 5, 31, 9),
    endTime: DateTime.utc(2026, 5, 31, 9, 30),
    type: AppointmentType.planned,
    status: AppointmentStatus.inProgress,
    createdAt: DateTime.utc(2026, 5, 31),
    updatedAt: DateTime.utc(2026, 5, 31),
  );
}

List<Override> _documentPageOverrides({
  VisitDocumentationState? docState,
  StubVisitDocumentationNotifier? docNotifier,
  VisitDetailViewState? detailView,
  Object? detailError,
  Override? detailViewProviderOverride,
  bool docLoading = false,
  Object? docError,
  AuthSessionState? auth,
  SpyEncounterActivePhaseNotifier? activePhaseNotifier,
  List<Override> extraOverrides = const [],
}) {
  final visit = docState?.visit ?? detailView?.visit ?? sampleEncounterVisit();
  return visitsProviderOverrides(
    visitId: encounterTestVisitId,
    auth: auth,
    docState: docNotifier == null ? docState : null,
    docNotifier: docNotifier,
    docLoading: docLoading,
    docError: docError,
    detailView: detailView ?? buildVisitDetailView(visit: visit),
    detailError: detailError,
    detailViewProviderOverride: detailViewProviderOverride,
    patientId: visit.patientId,
    patientSafety: buildPatientSafetyContext(),
    activePhaseNotifier: activePhaseNotifier,
    extraOverrides: [
      patientDetailProvider(visit.patientId).overrideWith((ref) async => _testPatient()),
      appointmentDetailProvider(visit.appointmentId).overrideWith((ref) async => _testAppointment()),
      ...extraOverrides,
    ],
  );
}

Future<void> _pumpVisitDocumentPage(
  WidgetTester tester, {
  bool startInEditMode = false,
  List<Override> overrides = const [],
}) async {
  await pumpVisitsSurface(
    tester,
    child: VisitDocumentPage(
      visitId: encounterTestVisitId,
      startInEditMode: startInEditMode,
    ),
    overrides: overrides,
  );
  await pumpVisitsFrames(tester);
}

AppButton _button(WidgetTester tester, String label) {
  return tester.widget<AppButton>(find.widgetWithText(AppButton, label));
}

Future<void> _tapVisibleButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

Future<void> _tapStepRailPhase(WidgetTester tester, String phaseLabel) async {
  final finder = find.bySemanticsLabel(phaseLabel);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

class _FlakyVisitDetailOverride {
  _FlakyVisitDetailOverride(this.visit);

  final VisitDetailViewState visit;
  var loadAttempts = 0;
}

class _FlakyDocNotifier extends VisitDocumentationNotifier {
  _FlakyDocNotifier(super.visitId, this._successState);

  final VisitDocumentationState _successState;
  var loadAttempts = 0;

  @override
  Future<VisitDocumentationState> build() async {
    loadAttempts++;
    if (loadAttempts < 2) {
      throw visitsRpcFailure(message: 'Documentation failed temporarily.');
    }
    return _successState;
  }
}

void main() {
  group('VisitDocumentPage — page build & async states', () {
    testWidgets('trivial: builds for in-progress visit with administrator session', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text(_appointmentBreadcrumbLabel), findsOneWidget);
      expect(find.text(_patientName), findsWidgets);
      expect(find.byType(VisitEncounterHeader), findsOneWidget);
      expect(find.byType(VisitEncounterStepRail), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsOneWidget);
    });

    testWidgets('trivial: shows visit detail loading scaffold', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          detailViewProviderOverride: visitDetailViewProvider(encounterTestVisitId).overrideWith(
            (ref) => Completer<VisitDetailViewState>().future,
          ),
        ),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Appointment'), findsOneWidget);
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsNothing);
    });

    testWidgets('trivial: shows documentation loading skeleton after detail resolves', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docLoading: true),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.byType(VisitEncounterHeader), findsOneWidget);
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsNothing);
    });

    testWidgets('advanced: detail error shows mapped message and Retry re-triggers load', (tester) async {
      final flaky = _FlakyVisitDetailOverride(buildVisitDetailView());

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          detailViewProviderOverride: visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) async {
            flaky.loadAttempts++;
            if (flaky.loadAttempts < 2) {
              throw visitsRpcFailure(
                code: 'UNAVAILABLE',
                message: 'Temporary detail failure.',
              );
            }
            return flaky.visit;
          }),
        ),
      );

      expect(find.text('Could not load visit'), findsOneWidget);
      expect(find.text('RpcFailure(UNAVAILABLE): Temporary detail failure.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(flaky.loadAttempts, 1);

      await tester.tap(find.text('Retry'));
      await pumpVisitsFrames(tester);

      expect(flaky.loadAttempts, 2);
      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Could not load visit'), findsNothing);
    });

    testWidgets('invalid state: not-found detail renders dedicated not-found view', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          detailError: visitsRpcFailure(code: 'NOT_FOUND', message: 'Visit not found.'),
        ),
      );

      expect(find.text('Visit not found'), findsNWidgets(2));
      expect(
        find.text('This visit may have been removed or you may not have access.'),
        findsOneWidget,
      );
      expect(find.text('Go back'), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsNothing);
    });

    testWidgets('invalid state: permission denied hides workspace', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          auth: visitsAuthSession(permissions: {PermissionKeys.patientsView}),
          docState: sampleEncounterDocState(),
        ),
      );

      expect(find.text('You do not have permission to document visits.'), findsOneWidget);
      expect(find.byType(VisitEncounterHeader), findsNothing);
      expect(find.byType(VisitEncounterStepContent), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets('edge case: missing branch access still renders workspace (no distinct denial view)', (tester) async {
      final visit = sampleEncounterVisit();
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          detailView: buildVisitDetailView(
            visit: visit,
            hasBranchAccess: false,
            canEditDocumentation: false,
          ),
          docState: sampleEncounterDocState(visit: visit),
        ),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.byType(VisitEncounterHeader), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsOneWidget);
      expect(find.text('You do not have permission to document visits.'), findsNothing);

      final editor = tester.widget<AppRichTextEditor>(find.byType(AppRichTextEditor).first);
      expect(editor.readOnly, isFalse);
    });

    testWidgets('advanced: documentation error shows Retry and reload succeeds', (tester) async {
      final flakyDoc = _FlakyDocNotifier(encounterTestVisitId, sampleEncounterDocState());

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          extraOverrides: [
            visitDocumentationProvider(encounterTestVisitId).overrideWith(() => flakyDoc),
          ],
        ),
      );

      expect(find.text('Could not load visit'), findsOneWidget);
      expect(
        find.text('RpcFailure(NOT_FOUND): Documentation failed temporarily.'),
        findsOneWidget,
      );
      expect(flakyDoc.loadAttempts, 1);

      await tester.tap(find.text('Retry'));
      await pumpVisitsFrames(tester);

      expect(flakyDoc.loadAttempts, 2);
      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Could not load visit'), findsNothing);
    });
  });

  group('VisitDocumentPage — structure & footer controls', () {
    testWidgets('trivial: breadcrumbs and encounter chrome are present for editable visit', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text(_appointmentBreadcrumbLabel), findsOneWidget);
      expect(find.text('Intake'), findsOneWidget);
      expect(find.text('Findings & Diagnosis'), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('trivial: Back is disabled on first documentation phase', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );

      expect(_button(tester, 'Back').onPressed, isNull);
      expect(_button(tester, 'Continue').onPressed, isNotNull);
    });

    testWidgets('advanced: Back is enabled after advancing past first phase', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );

      await _tapVisibleButton(tester, 'Continue');
      await pumpVisitsFrames(tester);

      expect(_button(tester, 'Back').onPressed, isNotNull);
    });

    testWidgets('advanced: plan phase Continue label is Review visit', (tester) async {
      final phaseSpy = SpyEncounterActivePhaseNotifier(encounterTestVisitId);

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          activePhaseNotifier: phaseSpy,
        ),
      );

      phaseSpy.setPhase(EncounterPhase.plan);
      await pumpVisitsFrames(tester);

      expect(find.text('Review visit'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
    });
  });

  group('VisitDocumentPage — interactions & navigation', () {
    testWidgets('trivial: Continue advances encounter phase', (tester) async {
      final phaseSpy = SpyEncounterActivePhaseNotifier(encounterTestVisitId);

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          activePhaseNotifier: phaseSpy,
        ),
      );

      final callsBefore = phaseSpy.setPhaseCallCount;
      await _tapVisibleButton(tester, 'Continue');
      await pumpVisitsFrames(tester);

      expect(phaseSpy.setPhaseCallCount, callsBefore + 1);
      expect(phaseSpy.lastPhase, EncounterPhase.objective);
    });

    testWidgets('trivial: Back returns to previous documentation phase', (tester) async {
      final phaseSpy = SpyEncounterActivePhaseNotifier(encounterTestVisitId);

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          activePhaseNotifier: phaseSpy,
        ),
      );

      await _tapVisibleButton(tester, 'Continue');
      await pumpVisitsFrames(tester);
      expect(phaseSpy.lastPhase, EncounterPhase.objective);

      await _tapVisibleButton(tester, 'Back');
      await pumpVisitsFrames(tester);

      expect(phaseSpy.lastPhase, EncounterPhase.subjective);
    });

    testWidgets('advanced: step rail selection switches phase', (tester) async {
      final phaseSpy = SpyEncounterActivePhaseNotifier(encounterTestVisitId);

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          activePhaseNotifier: phaseSpy,
        ),
      );

      final callsBefore = phaseSpy.setPhaseCallCount;
      await _tapStepRailPhase(tester, 'Treatment');
      await pumpVisitsFrames(tester);

      expect(phaseSpy.setPhaseCallCount, greaterThan(callsBefore));
      expect(phaseSpy.lastPhase, EncounterPhase.plan);
    });

    testWidgets('advanced: plan Continue opens review phase', (tester) async {
      final phaseSpy = SpyEncounterActivePhaseNotifier(encounterTestVisitId);

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          activePhaseNotifier: phaseSpy,
        ),
      );

      phaseSpy.setPhase(EncounterPhase.plan);
      await pumpVisitsFrames(tester);

      await _tapVisibleButton(tester, 'Review visit');
      await pumpVisitsFrames(tester);

      expect(phaseSpy.lastPhase, EncounterPhase.review);
    });

    testWidgets('trivial: Calendar breadcrumb navigates to appointments calendar stub', (tester) async {
      await pumpVisitsRouter(
        tester,
        home: VisitDocumentPage(visitId: encounterTestVisitId),
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );
      await pumpVisitsFrames(tester);

      await tester.tap(find.text('Calendar'));
      await pumpVisitsFrames(tester);

      expect(find.text('stub:appointments-calendar'), findsOneWidget);
      expect(find.byKey(const Key('route_appointments-calendar')), findsOneWidget);
    });

    testWidgets('trivial: appointment breadcrumb navigates to appointment detail stub', (tester) async {
      await pumpVisitsRouter(
        tester,
        home: VisitDocumentPage(visitId: encounterTestVisitId),
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );
      await pumpVisitsFrames(tester);

      await tester.tap(find.text(_appointmentBreadcrumbLabel));
      await pumpVisitsFrames(tester);

      expect(
        find.text('stub:appointment-$encounterTestAppointmentId'),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('route_appointment-$encounterTestAppointmentId')),
        findsOneWidget,
      );
    });
  });

  group('VisitDocumentPage — query-param & visit status behavior', () {
    testWidgets('advanced: startInEditMode enters workspace edit mode', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(workspaceEditMode: WorkspaceEditMode.viewing),
      );

      await _pumpVisitDocumentPage(
        tester,
        startInEditMode: true,
        overrides: _documentPageOverrides(docNotifier: docNotifier),
      );

      expect(docNotifier.enterWorkspaceEditModeCallCount, 1);

      final editor = tester.widget<AppRichTextEditor>(find.byType(AppRichTextEditor).first);
      expect(editor.readOnly, isFalse);
    });

    testWidgets('regression: completed visit auto-opens Summary and hides documentation footer', (tester) async {
      final completedVisit = sampleEncounterVisit(status: VisitStatus.completed);
      final docState = sampleEncounterDocState(
        visit: completedVisit,
        persistedVisit: completedVisit,
        workspaceEditMode: WorkspaceEditMode.viewing,
        noteEditMode: DocumentationEditMode.readOnly,
      );

      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          detailView: buildVisitDetailView(visit: completedVisit),
          docState: docState,
        ),
      );

      expect(find.text('Review visit'), findsWidgets);
      expect(find.text('Verify intake, findings, and treatment before finalizing this encounter.'), findsOneWidget);
      expect(find.byType(VisitEncounterHeader), findsNothing);
      expect(find.text('Back'), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(find.byType(AppRichTextEditor), findsNothing);
    });

    testWidgets('trivial: in-progress visit does not auto-open Summary', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docState: sampleEncounterDocState()),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.byType(VisitEncounterHeader), findsOneWidget);
      expect(find.text('Intake'), findsOneWidget);
      expect(find.text('Verify intake, findings, and treatment before finalizing this encounter.'), findsNothing);
    });
  });
}
