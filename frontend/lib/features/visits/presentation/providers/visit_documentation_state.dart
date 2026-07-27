import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Clinical note save lifecycle on the visit documentation screen.
enum DocumentationSaveStatus { idle, saving, saved, stale, error }

/// Whether the clinical note section is in editing or read-only-after-save mode.
enum DocumentationEditMode { editing, readOnly }

/// Whether the encounter workspace allows mutations (completed visits default to viewing).
enum WorkspaceEditMode { viewing, editing }

@immutable
class VisitDocumentationState {
  const VisitDocumentationState({
    required this.persistedVisit,
    required this.complaint,
    required this.history,
    required this.examination,
    required this.diagnosis,
    required this.plan,
    required this.expectedUpdatedAt,
    this.richTextDrafts = const {},
    this.predefinedVitalSigns = const [],
    this.encounterDraft = const VisitEncounterDraft(),
    this.saveStatus = DocumentationSaveStatus.idle,
    this.noteEditMode = DocumentationEditMode.editing,
    this.workspaceEditMode = WorkspaceEditMode.editing,
    this.errorMessage,
    this.conflictingServerNote,
    this.staleServerUpdatedAt,
  });

  /// Last server-loaded visit snapshot (without draft overlay).
  final VisitDetail persistedVisit;
  final String complaint;
  final String history;
  final String examination;
  final String diagnosis;
  final String plan;
  final DateTime expectedUpdatedAt;
  final Map<ClinicalNoteSection, List<dynamic>> richTextDrafts;
  final List<CatalogItem> predefinedVitalSigns;
  final VisitEncounterDraft encounterDraft;
  final DocumentationSaveStatus saveStatus;
  final DocumentationEditMode noteEditMode;
  final WorkspaceEditMode workspaceEditMode;
  final String? errorMessage;
  final VisitClinicalNote? conflictingServerNote;
  final DateTime? staleServerUpdatedAt;

  VisitDetail get effectiveVisit => encounterDraft.applyTo(persistedVisit);

  VisitDetail get visit => effectiveVisit;

  bool canEditWorkspace(bool hasEditPermission) {
    if (!hasEditPermission) {
      return false;
    }
    if (persistedVisit.status != VisitStatus.completed) {
      return true;
    }
    return workspaceEditMode == WorkspaceEditMode.editing;
  }

  bool get hasUnsavedDraft {
    if (saveStatus == DocumentationSaveStatus.saving) {
      return false;
    }
    if (saveStatus == DocumentationSaveStatus.stale) {
      return true;
    }
    return _clinicalNoteDiffersFromPersisted();
  }

  bool get clinicalNoteDiffersFromPersisted => _clinicalNoteDiffersFromPersisted();

  bool _clinicalNoteDiffersFromPersisted() {
    final persisted = persistedVisit.documentation;
    return complaint.trim() != (persisted?.complaint ?? '').trim() ||
        history.trim() != (persisted?.history ?? '').trim() ||
        examination.trim() != (persisted?.examination ?? '').trim() ||
        diagnosis.trim() != (persisted?.diagnosis ?? '').trim() ||
        plan.trim() != (persisted?.plan ?? '').trim();
  }

  bool get hasPendingEncounterDraft => !encounterDraft.isEmpty;

  bool get needsPersistBeforeSubmit => clinicalNoteDiffersFromPersisted || hasPendingEncounterDraft;

  bool get hasUnsavedChanges => hasUnsavedDraft || hasPendingEncounterDraft;

  bool get needsSaveBeforeLeaving => hasUnsavedChanges;

  PatientSafetyContext effectivePatientSafety(PatientSafetyContext base) => encounterDraft.patientSafety.applyTo(base);

  VisitDocumentationState copyWith({
    VisitDetail? persistedVisit,
    String? complaint,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
    DateTime? expectedUpdatedAt,
    Map<ClinicalNoteSection, List<dynamic>>? richTextDrafts,
    List<CatalogItem>? predefinedVitalSigns,
    VisitEncounterDraft? encounterDraft,
    DocumentationSaveStatus? saveStatus,
    DocumentationEditMode? noteEditMode,
    WorkspaceEditMode? workspaceEditMode,
    String? errorMessage,
    VisitClinicalNote? conflictingServerNote,
    DateTime? staleServerUpdatedAt,
    bool clearError = false,
    bool clearStaleConflict = false,
  }) {
    return VisitDocumentationState(
      persistedVisit: persistedVisit ?? this.persistedVisit,
      complaint: complaint ?? this.complaint,
      history: history ?? this.history,
      examination: examination ?? this.examination,
      diagnosis: diagnosis ?? this.diagnosis,
      plan: plan ?? this.plan,
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      richTextDrafts: richTextDrafts ?? this.richTextDrafts,
      predefinedVitalSigns: predefinedVitalSigns ?? this.predefinedVitalSigns,
      encounterDraft: encounterDraft ?? this.encounterDraft,
      saveStatus: saveStatus ?? this.saveStatus,
      noteEditMode: noteEditMode ?? this.noteEditMode,
      workspaceEditMode: workspaceEditMode ?? this.workspaceEditMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      conflictingServerNote: clearStaleConflict ? null : (conflictingServerNote ?? this.conflictingServerNote),
      staleServerUpdatedAt: clearStaleConflict ? null : (staleServerUpdatedAt ?? this.staleServerUpdatedAt),
    );
  }

  static VisitDocumentationState fromVisit(VisitDetail visit, {List<CatalogItem> predefinedVitalSigns = const []}) {
    final note = visit.documentation;
    final workspaceEditMode = visit.status == VisitStatus.completed
        ? WorkspaceEditMode.viewing
        : WorkspaceEditMode.editing;
    return VisitDocumentationState(
      persistedVisit: visit,
      complaint: note?.complaint ?? '',
      history: note?.history ?? '',
      examination: note?.examination ?? '',
      diagnosis: note?.diagnosis ?? '',
      plan: note?.plan ?? '',
      expectedUpdatedAt: note?.updatedAt ?? visit.updatedAt ?? DateTime.now().toUtc(),
      predefinedVitalSigns: predefinedVitalSigns,
      workspaceEditMode: workspaceEditMode,
      noteEditMode: workspaceEditMode == WorkspaceEditMode.editing
          ? DocumentationEditMode.editing
          : DocumentationEditMode.readOnly,
    );
  }
}
