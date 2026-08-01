import 'dart:async';

import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

=======
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
>>>>>>> master
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

<<<<<<< HEAD
=======
import '../../helpers/breadcrumb_test_support.dart';
>>>>>>> master
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
<<<<<<< HEAD
=======
  Override? detailViewProviderOverride,
>>>>>>> master
  bool docLoading = false,
  Object? docError,
  AuthSessionState? auth,
  SpyEncounterActivePhaseNotifier? activePhaseNotifier,
  List<Override> extraOverrides = const [],
<<<<<<< HEAD
=======
  BreadcrumbTrail? breadcrumbTrail,
>>>>>>> master
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
<<<<<<< HEAD
    patientId: visit.patientId,
    patientSafety: buildPatientSafetyContext(),
    activePhaseNotifier: activePhaseNotifier,
=======
    detailViewProviderOverride: detailViewProviderOverride,
    patientId: visit.patientId,
    patientSafety: buildPatientSafetyContext(),
    activePhaseNotifier: activePhaseNotifier,
    breadcrumbTrail: breadcrumbTrail,
>>>>>>> master
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

<<<<<<< HEAD
=======
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

>>>>>>> master
class _FlakyVisitDetailOverride {
  _FlakyVisitDetailOverride(this.visit);

  final VisitDetailViewState visit;
  var loadAttempts = 0;
}

class _FlakyDocNotifier extends VisitDocumentationNotifier {
<<<<<<< HEAD
  _FlakyDocNotifier(this._visitId, this._successState);

  final String _visitId;
=======
  _FlakyDocNotifier(super.visitId, this._successState);

>>>>>>> master
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

<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
>>>>>>> master
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
<<<<<<< HEAD
          extraOverrides: [
            visitDetailViewProvider(encounterTestVisitId).overrideWith(
              (ref) => Completer<VisitDetailViewState>().future,
            ),
          ],
        ),
      );

      expect(find.text('Visit documentation'), findsOneWidget);
      expect(find.text('Appointment'), findsOneWidget);
=======
          detailViewProviderOverride: visitDetailViewProvider(encounterTestVisitId).overrideWith(
            (ref) => Completer<VisitDetailViewState>().future,
          ),
        ),
      );

      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Calendar'), findsOneWidget);
>>>>>>> master
      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(VisitEncounterStepContent), findsNothing);
    });

    testWidgets('trivial: shows documentation loading skeleton after detail resolves', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(docLoading: true),
      );

<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
      expect(find.text(_patientName), findsWidgets);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Loading…'), findsOneWidget);
>>>>>>> master
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
<<<<<<< HEAD
          extraOverrides: [
            visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) async {
              flaky.loadAttempts++;
              if (flaky.loadAttempts < 2) {
                throw visitsRpcFailure(message: 'Temporary detail failure.');
              }
              return flaky.visit;
            }),
          ],
=======
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
>>>>>>> master
        ),
      );

      expect(find.text('Could not load visit'), findsOneWidget);
<<<<<<< HEAD
      expect(find.text('RpcFailure(NOT_FOUND): Temporary detail failure.'), findsOneWidget);
=======
      expect(find.text('RpcFailure(UNAVAILABLE): Temporary detail failure.'), findsOneWidget);
>>>>>>> master
      expect(find.text('Retry'), findsOneWidget);
      expect(flaky.loadAttempts, 1);

      await tester.tap(find.text('Retry'));
      await pumpVisitsFrames(tester);

      expect(flaky.loadAttempts, 2);
<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
>>>>>>> master
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

<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
>>>>>>> master
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
<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
>>>>>>> master
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

<<<<<<< HEAD
      await tester.tap(find.text('Continue'));
=======
      await _tapVisibleButton(tester, 'Continue');
>>>>>>> master
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
<<<<<<< HEAD
      await tester.tap(find.text('Continue'));
=======
      await _tapVisibleButton(tester, 'Continue');
>>>>>>> master
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

<<<<<<< HEAD
      await tester.tap(find.text('Continue'));
      await pumpVisitsFrames(tester);
      expect(phaseSpy.lastPhase, EncounterPhase.objective);

      await tester.tap(find.text('Back'));
=======
      await _tapVisibleButton(tester, 'Continue');
      await pumpVisitsFrames(tester);
      expect(phaseSpy.lastPhase, EncounterPhase.objective);

      await _tapVisibleButton(tester, 'Back');
>>>>>>> master
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
<<<<<<< HEAD
      await tester.tap(find.text('Treatment'));
=======
      await _tapStepRailPhase(tester, 'Treatment');
>>>>>>> master
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

<<<<<<< HEAD
      await tester.tap(find.text('Review visit'));
=======
      await _tapVisibleButton(tester, 'Review visit');
>>>>>>> master
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

<<<<<<< HEAD
=======
  group('VisitDocumentPage — breadcrumb trails', () {
    testWidgets('invoice origin shows Invoices → invoice → visit documentation', (tester) async {
      const invoiceNumber = 'INV-MAIN-000001';
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          breadcrumbTrail: invoiceToVisitTrail(
            invoiceId: 'inv-1',
            invoiceNumber: invoiceNumber,
            visitId: encounterTestVisitId,
          ),
        ),
      );

      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text(invoiceNumber), findsOneWidget);
      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Calendar'), findsNothing);
      expect(find.text(_appointmentBreadcrumbLabel), findsNothing);
    });

    testWidgets('invoice crumb navigates to invoice detail stub', (tester) async {
      const invoiceId = 'inv-1';
      const invoiceNumber = 'INV-MAIN-000001';

      await pumpVisitsRouter(
        tester,
        home: VisitDocumentPage(visitId: encounterTestVisitId),
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          breadcrumbTrail: invoiceToVisitTrail(
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
            visitId: encounterTestVisitId,
          ),
        ),
      );
      await pumpVisitsFrames(tester);

      await tester.tap(find.text(invoiceNumber));
      await pumpVisitsFrames(tester);

      expect(find.byKey(Key('route_invoice-$invoiceId')), findsOneWidget);
      expect(find.text('stub:invoice-$invoiceId'), findsOneWidget);
    });

    testWidgets('deep link weak trail upgrades to calendar appointment path', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          breadcrumbTrail: weakVisitDocumentTrail(encounterTestVisitId),
        ),
      );

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text(_appointmentBreadcrumbLabel), findsOneWidget);
      expect(find.text('Invoices'), findsNothing);
    });

    testWidgets('patients origin shows Patients → name → visit documentation', (tester) async {
      await _pumpVisitDocumentPage(
        tester,
        overrides: _documentPageOverrides(
          docState: sampleEncounterDocState(),
          breadcrumbTrail: patientsToVisitTrail(
            patientId: encounterTestPatientId,
            patientName: _patientName,
            visitId: encounterTestVisitId,
          ),
        ),
      );

      expect(find.text('Patients'), findsOneWidget);
      expect(find.text(_patientName), findsWidgets);
      expect(find.text('Visit documentation'), findsNWidgets(2));
      expect(find.text('Calendar'), findsNothing);
    });
  });

>>>>>>> master
  group('VisitDocumentPage — query-param & visit status behavior', () {
    testWidgets('advanced: startInEditMode enters workspace edit mode', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(workspaceEditMode: WorkspaceEditMode.viewing),
      );

      await _pumpVisitDocumentPage(
<<<<<<< HEAD
=======
        tester,
>>>>>>> master
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

<<<<<<< HEAD
      expect(find.text('Visit documentation'), findsOneWidget);
=======
      expect(find.text('Visit documentation'), findsNWidgets(2));
>>>>>>> master
      expect(find.byType(VisitEncounterHeader), findsOneWidget);
      expect(find.text('Intake'), findsOneWidget);
      expect(find.text('Verify intake, findings, and treatment before finalizing this encounter.'), findsNothing);
    });
  });
}
