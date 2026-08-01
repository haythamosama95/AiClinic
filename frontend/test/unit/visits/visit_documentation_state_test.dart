import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/visit_encounter_test_support.dart';

void main() {
  group('VisitDocumentationState.fromVisit', () {
    test('trivial: copies documentation fields from visit', () {
      final visit = sampleEncounterVisit(
        documentation: buildVisitClinicalNote(
          complaint: 'Fever',
          history: 'Two days',
          examination: 'Normal',
          diagnosis: 'URI',
          plan: 'Rest',
        ),
      );

      final state = VisitDocumentationState.fromVisit(visit);

      expect(state.complaint, 'Fever');
      expect(state.history, 'Two days');
      expect(state.examination, 'Normal');
      expect(state.diagnosis, 'URI');
      expect(state.plan, 'Rest');
      expect(state.persistedVisit, visit);
      expect(state.visit, visit);
      expect(state.encounterDraft.isEmpty, isTrue);
      expect(state.saveStatus, DocumentationSaveStatus.idle);
    });

    test('advanced: in-progress visit opens workspace and note in editing mode', () {
      final state = VisitDocumentationState.fromVisit(sampleEncounterVisit());

      expect(state.workspaceEditMode, WorkspaceEditMode.editing);
      expect(state.noteEditMode, DocumentationEditMode.editing);
    });

    test('advanced: completed visit defaults to viewing workspace and read-only note', () {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit);

      expect(state.workspaceEditMode, WorkspaceEditMode.viewing);
      expect(state.noteEditMode, DocumentationEditMode.readOnly);
    });

    test('edge case: uses documentation updatedAt as expectedUpdatedAt when present', () {
      final token = DateTime.utc(2026, 6, 1, 12);
      final visit = sampleEncounterVisit(
        documentation: VisitClinicalNote(updatedAt: token),
        updatedAt: DateTime.utc(2026, 5, 31, 10),
      );

      expect(VisitDocumentationState.fromVisit(visit).expectedUpdatedAt, token);
    });
  });

  group('VisitDocumentationState.effectiveVisit', () {
    test('trivial: matches persisted visit when draft is empty', () {
      final visit = sampleEncounterVisit(
        vitalSigns: [buildVisitVitalSign()],
      );
      final state = sampleEncounterDocState(visit: visit);

      expect(state.effectiveVisit.vitalSigns, visit.vitalSigns);
      expect(state.effectiveVisit, equals(visit));
    });

    test('advanced: overlays pending vital sign onto persisted visit', () {
      final persisted = sampleEncounterVisit();
      final pending = buildVisitVitalSign(id: 'draft:vs-1', name: 'Temp', value: '38.5', unit: 'C');
      final state = sampleEncounterDocState(
        visit: persisted,
        persistedVisit: persisted,
        encounterDraft: buildVisitEncounterDraft(pendingVitalSigns: [pending]),
      );

      expect(state.effectiveVisit.vitalSigns, [pending]);
      expect(state.persistedVisit.vitalSigns, isEmpty);
    });

    test('advanced: hides archived persisted vital sign from effective visit', () {
      final persisted = sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]);
      final state = sampleEncounterDocState(
        visit: persisted,
        persistedVisit: persisted,
        encounterDraft: buildVisitEncounterDraft(archivedVitalSignIds: {encounterTestVitalSignId}),
      );

      expect(state.effectiveVisit.vitalSigns, isEmpty);
      expect(state.persistedVisit.vitalSigns, hasLength(1));
    });
  });

  group('VisitDocumentationState.copyWith', () {
    test('trivial: updates only the targeted field', () {
      final base = sampleEncounterDocState(complaint: 'A', history: 'B');

      final next = base.copyWith(complaint: 'Changed');

      expect(next.complaint, 'Changed');
      expect(next.history, 'B');
      expect(base.complaint, 'A');
    });

    test('advanced: clearError removes errorMessage without passing null explicitly', () {
      final base = sampleEncounterDocState(errorMessage: 'Failed');

      final cleared = base.copyWith(clearError: true);
      final explicit = base.copyWith(errorMessage: null);

      expect(cleared.errorMessage, isNull);
      expect(explicit.errorMessage, 'Failed');
    });

    test('edge case: omits unspecified fields from the new instance', () {
      final token = DateTime.utc(2026, 6, 2);
      final base = sampleEncounterDocState(expectedUpdatedAt: token);

      expect(base.copyWith(complaint: 'x').expectedUpdatedAt, token);
    });
  });

  group('VisitDocumentationState.canEditWorkspace', () {
    test('trivial: denies edit without permission regardless of status', () {
      final inProgress = VisitDocumentationState.fromVisit(sampleEncounterVisit());
      final completed = VisitDocumentationState.fromVisit(
        sampleEncounterVisit(status: VisitStatus.completed),
      );

      expect(inProgress.canEditWorkspace(false), isFalse);
      expect(completed.canEditWorkspace(false), isFalse);
    });

    test('advanced: completed visits are read-only until workspace edit mode is enabled', () {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final viewing = VisitDocumentationState.fromVisit(visit);

      expect(viewing.canEditWorkspace(true), isFalse);

      final editing = viewing.copyWith(workspaceEditMode: WorkspaceEditMode.editing);
      expect(editing.canEditWorkspace(true), isTrue);
    });

    test('advanced: in-progress visits remain editable without workspace edit mode', () {
      final viewing = VisitDocumentationState.fromVisit(sampleEncounterVisit());

      expect(viewing.canEditWorkspace(true), isTrue);
    });
  });

  group('VisitDocumentationState draft diff flags', () {
    test('trivial: clinicalNoteDiffersFromPersisted is false when sections match persisted', () {
      final visit = sampleEncounterVisit(documentation: buildVisitClinicalNote(complaint: 'Same'));
      final state = sampleEncounterDocState(
        visit: visit,
        persistedVisit: visit,
        complaint: 'Same',
      );

      expect(state.clinicalNoteDiffersFromPersisted, isFalse);
      expect(state.hasUnsavedDraft, isFalse);
      expect(state.needsPersistBeforeSubmit, isFalse);
    });

    test('advanced: trim-aware comparison ignores surrounding whitespace', () {
      final visit = sampleEncounterVisit(documentation: buildVisitClinicalNote(complaint: 'Same'));
      final state = sampleEncounterDocState(
        visit: visit,
        persistedVisit: visit,
        complaint: '  Same  ',
      );

      expect(state.clinicalNoteDiffersFromPersisted, isFalse);
    });

    test('advanced: hasUnsavedDraft is true when complaint differs', () {
      final visit = sampleEncounterVisit();
      final state = sampleEncounterDocState(
        visit: visit,
        persistedVisit: visit,
        complaint: 'Edited',
      );

      expect(state.hasUnsavedDraft, isTrue);
      expect(state.needsPersistBeforeSubmit, isTrue);
      expect(state.hasUnsavedChanges, isTrue);
    });

    test('advanced: hasPendingEncounterDraft when structured draft is non-empty', () {
      final state = sampleEncounterDocState(
        encounterDraft: buildVisitEncounterDraft(
          pendingVitalSigns: [buildVisitVitalSign(id: 'draft:1')],
        ),
      );

      expect(state.hasPendingEncounterDraft, isTrue);
      expect(state.needsPersistBeforeSubmit, isTrue);
      expect(state.clinicalNoteDiffersFromPersisted, isFalse);
    });

    test('edge case: saving status suppresses hasUnsavedDraft even when text differs', () {
      final visit = sampleEncounterVisit();
      final state = sampleEncounterDocState(
        visit: visit,
        persistedVisit: visit,
        complaint: 'Edited',
        saveStatus: DocumentationSaveStatus.saving,
      );

      expect(state.hasUnsavedDraft, isFalse);
    });

    test('edge case: stale status always reports hasUnsavedDraft', () {
      final visit = sampleEncounterVisit(documentation: buildVisitClinicalNote(complaint: 'Same'));
      final state = sampleEncounterDocState(
        visit: visit,
        persistedVisit: visit,
        complaint: 'Same',
        saveStatus: DocumentationSaveStatus.stale,
      );

      expect(state.hasUnsavedDraft, isTrue);
    });
  });

  group('VisitDocumentationState.effectivePatientSafety', () {
    test('trivial: applies patient safety draft overlay to base context', () {
      final base = buildPatientSafetyContext();
      final state = sampleEncounterDocState(
        encounterDraft: buildVisitEncounterDraft(
          patientSafety: const PatientSafetyDraft(
            pendingAllergies: [PatientAllergy(id: 'draft:a1', substance: 'Latex')],
          ),
        ),
      );

      final merged = state.effectivePatientSafety(base);

      expect(merged.allergies, [const PatientAllergy(id: 'draft:a1', substance: 'Latex')]);
    });
  });

  group('VisitDocumentationState equality', () {
    test('stupid usage: does not implement value equality', () {
      final a = sampleEncounterDocState(complaint: 'x');
      final b = sampleEncounterDocState(complaint: 'x');

      expect(a == b, isFalse);
    });
  });
}
