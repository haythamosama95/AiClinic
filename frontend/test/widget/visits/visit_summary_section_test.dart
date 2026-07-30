import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_summary_section.dart';

import '../../helpers/role_permission_seed.dart';
import 'visit_widget_test_harness.dart';

Future<StubVisitDocumentationNotifier> _pumpSummary(
  WidgetTester tester, {
  required StubVisitDocumentationNotifier docNotifier,
  AuthSessionState? auth,
  PatientSafetyContext? patientSafety,
  bool patientSafetyLoading = false,
  Object? patientSafetyError,
  SpyEncounterActivePhaseNotifier? activePhaseNotifier,
}) async {
  await pumpVisitsSurface(
    tester,
    child: SingleChildScrollView(
      child: VisitSummarySection(visitId: encounterTestVisitId),
    ),
    overrides: visitsProviderOverrides(
      visitId: encounterTestVisitId,
      patientId: encounterTestPatientId,
      docNotifier: docNotifier,
      auth: auth,
      patientSafety: patientSafety,
      patientSafetyLoading: patientSafetyLoading,
      patientSafetyError: patientSafetyError,
      activePhaseNotifier: activePhaseNotifier ?? SpyEncounterActivePhaseNotifier(encounterTestVisitId),
    ),
  );
  await pumpVisitsFrames(tester);
  return docNotifier;
}

Future<void> _tapSummaryButton(WidgetTester tester, String label) async {
  final target = find.widgetWithText(AppButton, label);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(target);
  await pumpVisitsFrames(tester);
}

StubVisitDocumentationNotifier _submittableDocNotifier({
  Future<CompleteVisitResult> Function()? onCompleteVisit,
  Object? completeVisitError,
  Future<bool> Function()? onSaveAll,
}) {
  final visit = sampleEncounterVisit(
    documentation: buildVisitClinicalNote(complaint: 'Headache'),
    vitalSigns: [buildVisitVitalSign()],
    investigations: [buildVisitInvestigation(note: 'Routine panel')],
    treatmentPlans: [
      buildVisitTreatmentPlanItem(
        dosage: '500mg',
        frequency: 'bd',
        duration: '7d',
      ),
    ],
    attachments: [buildVisitAttachmentItem()],
  );
  return StubVisitDocumentationNotifier(
    encounterTestVisitId,
    sampleEncounterDocState(
      visit: visit,
      complaint: 'Headache',
      history: 'Three-day onset',
      examination: 'Alert and oriented',
      diagnosis: 'Tension headache',
      plan: 'Rest and fluids',
      workspaceEditMode: WorkspaceEditMode.editing,
    ),
    onCompleteVisit: onCompleteVisit,
    completeVisitError: completeVisitError,
    onSaveAll: onSaveAll,
  );
}

void main() {
  group('VisitSummarySection — ledger', () {
    testWidgets('trivial: renders documented intake, findings, and treatment rows', (tester) async {
      final docNotifier = _submittableDocNotifier();
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        patientSafety: buildPatientSafetyContext(
          allergies: [buildPatientAllergy(reaction: 'Rash')],
          currentMedications: [buildPatientMedication(note: 'Daily')],
          chronicConditions: [buildPatientChronicCondition(note: 'Managed')],
        ),
      );

      expect(find.text('Review visit'), findsOneWidget);
      expect(find.text('Verify intake, findings, and treatment before finalizing this encounter.'), findsOneWidget);
      expect(find.text('Intake'), findsOneWidget);
      expect(find.text('Findings & diagnosis'), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
      expect(find.text('Headache'), findsOneWidget);
      expect(find.text('Three-day onset'), findsOneWidget);
      expect(find.text('Alert and oriented'), findsOneWidget);
      expect(find.text('Tension headache'), findsOneWidget);
      expect(find.text('Rest and fluids'), findsOneWidget);
      expect(find.textContaining('Blood Pressure'), findsOneWidget);
      expect(find.textContaining('120/80'), findsOneWidget);
      expect(find.textContaining('Complete Blood Count'), findsOneWidget);
      expect(find.textContaining('Amoxicillin'), findsOneWidget);
      expect(find.text('Lab PDF'), findsOneWidget);
      expect(find.textContaining('Penicillin'), findsOneWidget);
      expect(find.textContaining('Rash'), findsOneWidget);
      expect(find.textContaining('Metformin'), findsOneWidget);
      expect(find.textContaining('Daily'), findsOneWidget);
      expect(find.textContaining('Type 2 diabetes'), findsOneWidget);
      expect(find.textContaining('Managed'), findsOneWidget);
    });

    testWidgets('trivial: empty documentation shows ledger empty-state copy', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(workspaceEditMode: WorkspaceEditMode.editing),
      );
      await _pumpSummary(tester, docNotifier: docNotifier);

      expect(find.text('—'), findsNWidgets(5));
      expect(find.text('None recorded'), findsNWidgets(4));
      expect(find.text('None ordered'), findsOneWidget);
      expect(find.text('None prescribed'), findsOneWidget);
      expect(find.text('No attachments'), findsOneWidget);
    });
  });

  group('VisitSummarySection — primary actions', () {
    testWidgets('trivial: in-progress submittable visit shows Finalize visit', (tester) async {
      final docNotifier = _submittableDocNotifier();
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      expect(find.widgetWithText(AppButton, 'Finalize visit'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Save changes'), findsNothing);
    });

    testWidgets('advanced: completed workspace edit with unsaved changes shows Save changes', (tester) async {
      final persisted = sampleEncounterVisit(
        status: VisitStatus.completed,
        documentation: buildVisitClinicalNote(complaint: 'Original'),
      );
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: persisted,
          persistedVisit: persisted,
          complaint: 'Updated complaint',
          workspaceEditMode: WorkspaceEditMode.editing,
          noteEditMode: DocumentationEditMode.editing,
        ),
      );
      await _pumpSummary(tester, docNotifier: docNotifier);

      expect(find.widgetWithText(AppButton, 'Save changes'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Finalize visit'), findsNothing);
    });

    testWidgets('edge case: completed visit without unsaved changes hides primary action', (tester) async {
      final completed = sampleEncounterVisit(
        status: VisitStatus.completed,
        documentation: buildVisitClinicalNote(complaint: 'Filed'),
      );
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: completed,
          persistedVisit: completed,
          complaint: 'Filed',
          workspaceEditMode: WorkspaceEditMode.viewing,
          noteEditMode: DocumentationEditMode.readOnly,
        ),
      );
      await _pumpSummary(tester, docNotifier: docNotifier);

      expect(find.widgetWithText(AppButton, 'Save changes'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Finalize visit'), findsNothing);
    });

    testWidgets('advanced: invoice permission routes Finalize visit to billing stub', (tester) async {
      final docNotifier = _submittableDocNotifier();
      await pumpVisitsRouter(
        tester,
        home: SingleChildScrollView(
          child: VisitSummarySection(visitId: encounterTestVisitId),
        ),
        overrides: visitsProviderOverrides(
          visitId: encounterTestVisitId,
          patientId: encounterTestPatientId,
          docNotifier: docNotifier,
          auth: visitsAuthSession(permissions: RolePermissionSeed.administrator),
        ),
      );
      await pumpVisitsFrames(tester);

      await _tapSummaryButton(tester, 'Finalize visit');
      await pumpVisitsFrames(tester);

      expect(docNotifier.completeVisitCallCount, 0);
      expect(find.text('stub:visit-billing-$encounterTestVisitId'), findsOneWidget);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('advanced: without invoice permission Finalize visit completes visit and opens dialog', (tester) async {
      final docNotifier = _submittableDocNotifier();
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      await _tapSummaryButton(tester, 'Finalize visit');
      await tester.pump(const Duration(milliseconds: 300));

      expect(docNotifier.completeVisitCallCount, 1);
      expect(find.byType(AppDialogPanel), findsOneWidget);
      expect(find.text('Visit completed'), findsOneWidget);
    });

    testWidgets('advanced: Save changes invokes saveAll and opens edited confirmation dialog', (tester) async {
      final persisted = sampleEncounterVisit(
        status: VisitStatus.completed,
        documentation: buildVisitClinicalNote(complaint: 'Original'),
      );
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: persisted,
          persistedVisit: persisted,
          complaint: 'Updated complaint',
          workspaceEditMode: WorkspaceEditMode.editing,
          noteEditMode: DocumentationEditMode.editing,
        ),
        onSaveAll: () async => true,
      );
      await _pumpSummary(tester, docNotifier: docNotifier);

      await _tapSummaryButton(tester, 'Save changes');
      await tester.pump(const Duration(milliseconds: 300));

      expect(docNotifier.saveAllCallCount, 1);
      expect(find.byType(AppDialogPanel), findsOneWidget);
      expect(find.text('Changes saved'), findsOneWidget);
    });
  });

  group('VisitSummarySection — edit visit', () {
    testWidgets('trivial: completed visit shows Edit visit control', (tester) async {
      final completed = sampleEncounterVisit(status: VisitStatus.completed);
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: completed,
          persistedVisit: completed,
          workspaceEditMode: WorkspaceEditMode.viewing,
          noteEditMode: DocumentationEditMode.readOnly,
        ),
      );
      final phaseNotifier = SpyEncounterActivePhaseNotifier(encounterTestVisitId);
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        activePhaseNotifier: phaseNotifier,
      );

      expect(find.widgetWithText(AppButton, 'Edit visit'), findsOneWidget);
    });

    testWidgets('advanced: tapping Edit visit enters workspace edit mode and selects plan phase', (tester) async {
      final completed = sampleEncounterVisit(status: VisitStatus.completed);
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: completed,
          persistedVisit: completed,
          workspaceEditMode: WorkspaceEditMode.viewing,
          noteEditMode: DocumentationEditMode.readOnly,
        ),
      );
      final phaseNotifier = SpyEncounterActivePhaseNotifier(encounterTestVisitId);
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        activePhaseNotifier: phaseNotifier,
      );

      final callsBefore = phaseNotifier.setPhaseCallCount;
      await _tapSummaryButton(tester, 'Edit visit');

      expect(docNotifier.enterWorkspaceEditModeCallCount, 1);
      expect(phaseNotifier.setPhaseCallCount, greaterThan(callsBefore));
      expect(phaseNotifier.lastPhase, EncounterPhase.plan);
    });
  });

  group('VisitSummarySection — submit readiness and failures', () {
    testWidgets('invalid state: empty documentation blocks finalize with readiness toast', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(workspaceEditMode: WorkspaceEditMode.editing),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      await _tapSummaryButton(tester, 'Finalize visit');

      expect(
        find.text('Enter at least one documentation field before submitting this visit.'),
        findsOneWidget,
      );
      expect(docNotifier.completeVisitCallCount, 0);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('invalid state: STALE_DOCUMENTATION completeVisit failure surfaces mapped toast', (tester) async {
      final docNotifier = _submittableDocNotifier(
        completeVisitError: visitsRpcFailure(code: 'STALE_DOCUMENTATION'),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      await _tapSummaryButton(tester, 'Finalize visit');

      expect(
        find.text('This visit note was updated elsewhere. Reload and try again.'),
        findsOneWidget,
      );
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('invalid state: generic completeVisit failure surfaces friendly toast', (tester) async {
      final docNotifier = _submittableDocNotifier(
        completeVisitError: StateError('RpcFailure raw internals'),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      await _tapSummaryButton(tester, 'Finalize visit');

      expect(find.text('Could not finalize the visit. Please try again.'), findsOneWidget);
      expect(find.textContaining('RpcFailure'), findsNothing);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('invalid state: RpcFailure with custom message surfaces failure.message', (tester) async {
      final docNotifier = _submittableDocNotifier(
        completeVisitError: RpcFailure(
          const RpcResult(
            success: false,
            errorCode: 'CUSTOM_BACKEND_ERROR',
            errorMessage: 'Backend rejected completion.',
          ),
        ),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: RolePermissionSeed.doctor),
      );

      await _tapSummaryButton(tester, 'Finalize visit');

      expect(find.text('Backend rejected completion.'), findsOneWidget);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('edge case: saveAll failure surfaces errorMessage toast', (tester) async {
      final persisted = sampleEncounterVisit(
        status: VisitStatus.completed,
        documentation: buildVisitClinicalNote(complaint: 'Original'),
      );
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: persisted,
          persistedVisit: persisted,
          complaint: 'Updated complaint',
          workspaceEditMode: WorkspaceEditMode.editing,
          noteEditMode: DocumentationEditMode.editing,
          errorMessage: 'Could not persist staged vitals.',
        ),
        onSaveAll: () async => false,
      );
      await _pumpSummary(tester, docNotifier: docNotifier);

      await _tapSummaryButton(tester, 'Save changes');

      expect(find.text('Could not persist staged vitals.'), findsOneWidget);
      expect(find.byType(AppDialog), findsNothing);
    });

  });

  group('VisitSummarySection — permissions', () {
    testWidgets('invalid state: missing visits.edit_soap blocks finalize with permission toast', (tester) async {
      final docNotifier = _submittableDocNotifier();
      final permissions = RolePermissionSeed.receptionist
          .where((key) => key != PermissionKeys.visitsEditSoap)
          .toSet();
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: permissions),
      );

      await _tapSummaryButton(tester, 'Finalize visit');

      expect(find.text('You do not have permission to finalize this visit.'), findsOneWidget);
      expect(docNotifier.completeVisitCallCount, 0);
    });

    testWidgets('invalid state: missing edit permission hides Save changes on completed visit', (tester) async {
      final persisted = sampleEncounterVisit(
        status: VisitStatus.completed,
        documentation: buildVisitClinicalNote(complaint: 'Original'),
      );
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          visit: persisted,
          persistedVisit: persisted,
          complaint: 'Updated complaint',
          workspaceEditMode: WorkspaceEditMode.editing,
        ),
      );
      final permissions = RolePermissionSeed.receptionist
          .where((key) => key != PermissionKeys.visitsEditSoap)
          .toSet();
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        auth: visitsAuthSession(permissions: permissions),
      );

      expect(find.widgetWithText(AppButton, 'Save changes'), findsNothing);
    });
  });

  group('VisitSummarySection — patient safety provider states', () {
    testWidgets('edge case: patient safety loading falls back to empty ledger copy', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          complaint: 'Fever',
          workspaceEditMode: WorkspaceEditMode.editing,
        ),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        patientSafetyLoading: true,
      );

      expect(find.text('None recorded'), findsNWidgets(4));
    });

    testWidgets('edge case: patient safety error falls back to empty ledger copy', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          complaint: 'Fever',
          workspaceEditMode: WorkspaceEditMode.editing,
        ),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        patientSafetyError: StateError('patient safety unavailable'),
      );

      expect(find.text('None recorded'), findsNWidgets(4));
      expect(find.textContaining('patient safety unavailable'), findsNothing);
    });

    testWidgets('trivial: staged patient safety draft overlays provider data in ledger', (tester) async {
      final docNotifier = StubVisitDocumentationNotifier(
        encounterTestVisitId,
        sampleEncounterDocState(
          complaint: 'Fever',
          workspaceEditMode: WorkspaceEditMode.editing,
          encounterDraft: buildVisitEncounterDraft(
            patientSafety: const PatientSafetyDraft(
              pendingAllergies: [
                PatientAllergy(id: 'draft-allergy', substance: 'Shellfish', reaction: 'Hives'),
              ],
            ),
          ),
        ),
      );
      await _pumpSummary(
        tester,
        docNotifier: docNotifier,
        patientSafety: buildPatientSafetyContext(
          allergies: [buildPatientAllergy(substance: 'Penicillin')],
        ),
      );

      expect(find.textContaining('Shellfish'), findsOneWidget);
      expect(find.textContaining('Hives'), findsOneWidget);
      expect(find.text('Penicillin'), findsNothing);
    });
  });

  group('VisitSummarySection — documentation loading', () {
    testWidgets('trivial: shows skeleton while documentation is loading', (tester) async {
      await pumpVisitsSurface(
        tester,
        child: VisitSummarySection(visitId: encounterTestVisitId),
        overrides: visitsProviderOverrides(
          visitId: encounterTestVisitId,
          patientId: encounterTestPatientId,
          docLoading: true,
        ),
      );
      await pumpVisitsFrames(tester);

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.text('Review visit'), findsNothing);
    });
  });
}
