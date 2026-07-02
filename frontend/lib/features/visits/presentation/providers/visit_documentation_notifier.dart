import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_paragraph_field.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';

/// Clinical note save lifecycle on the visit documentation screen.
enum DocumentationSaveStatus { idle, saving, saved, stale, error }

/// Whether the clinical note section is in editing or read-only-after-save mode.
enum DocumentationEditMode { editing, readOnly }

/// Whether the encounter workspace allows mutations (completed visits default to viewing).
enum WorkspaceEditMode { viewing, editing }

@immutable
class VisitDocumentationState {
  const VisitDocumentationState({
    required this.visit,
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
  });

  /// Visit data shown in the workspace (persisted rows plus in-memory draft overlay).
  final VisitDetail visit;

  /// Last server-loaded visit snapshot (without draft overlay).
  final VisitDetail persistedVisit;
  final String complaint;
  final String history;
  final String examination;
  final String diagnosis;
  final String plan;
  final DateTime expectedUpdatedAt;

  /// In-session Quill delta JSON per section. Preserves rich formatting while
  /// navigating the encounter workspace; not persisted to the backend.
  final Map<ClinicalNoteSection, List<dynamic>> richTextDrafts;
  final List<CatalogItem> predefinedVitalSigns;
  final VisitEncounterDraft encounterDraft;
  final DocumentationSaveStatus saveStatus;
  final DocumentationEditMode noteEditMode;
  final WorkspaceEditMode workspaceEditMode;
  final String? errorMessage;

  /// Whether the workspace UI should allow edits (permission + lifecycle + edit mode).
  bool canEditWorkspace(bool hasEditPermission) {
    if (!hasEditPermission) {
      return false;
    }
    if (visit.status != VisitStatus.completed) {
      return true;
    }
    return workspaceEditMode == WorkspaceEditMode.editing;
  }

  /// Whether the clinical note draft has unsaved changes.
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

  /// Whether local documentation still needs to be written to the server before submit.
  bool get needsPersistBeforeSubmit => clinicalNoteDiffersFromPersisted || hasPendingEncounterDraft;

  bool get hasUnsavedChanges => hasUnsavedDraft || hasPendingEncounterDraft;

  /// @deprecated Use [hasUnsavedDraft] with page-level permission gating.
  bool get needsSaveBeforeLeaving => hasUnsavedChanges;

  PatientSafetyContext effectivePatientSafety(PatientSafetyContext base) => encounterDraft.patientSafety.applyTo(base);

  /// Persisted visit rows merged with the in-memory encounter draft overlay.
  VisitDetail get effectiveVisit => encounterDraft.applyTo(persistedVisit);

  VisitDocumentationState copyWith({
    VisitDetail? visit,
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
    bool clearError = false,
  }) {
    return VisitDocumentationState(
      visit: visit ?? this.visit,
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
    );
  }

  static VisitDocumentationState fromVisit(VisitDetail visit, {List<CatalogItem> predefinedVitalSigns = const []}) {
    final note = visit.documentation;
    final workspaceEditMode = visit.status == VisitStatus.completed
        ? WorkspaceEditMode.viewing
        : WorkspaceEditMode.editing;
    return VisitDocumentationState(
      visit: visit,
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

final visitDocumentationProvider = AsyncNotifierProvider.autoDispose
    .family<VisitDocumentationNotifier, VisitDocumentationState, String>(VisitDocumentationNotifier.new);

/// Family arg is injected by [visitDocumentationProvider] via `NotifierT Function(String)`.
class VisitDocumentationNotifier extends AsyncNotifier<VisitDocumentationState> {
  VisitDocumentationNotifier(this._visitId);

  final String _visitId;
  final Set<VoidCallback> _clinicalNoteFlushCallbacks = {};

  @override
  Future<VisitDocumentationState> build() async {
    return _load();
  }

  Future<VisitDocumentationState> _load() async {
    final visitId = _visitId.trim();
    if (visitId.isEmpty) {
      throw StateError('Visit id is required.');
    }

    final repo = ref.read(visitRepositoryProvider);
    final visit = await repo.getVisit(visitId: visitId);
    final predefinedVitalSigns = await repo.listPredefinedVitalSigns();
    return VisitDocumentationState.fromVisit(visit, predefinedVitalSigns: predefinedVitalSigns);
  }

  bool _canEditVisit(VisitDetail visit) {
    final permissions = ref.read(permissionServiceProvider);
    final branchIds = ref.read(authSessionProvider).context?.branchIds ?? const <String>[];
    // Post-submit editing allowed on completed visits (013 FR-017, V1-5 parity).
    return permissions.canEditVisitSoap() && branchIds.contains(visit.branchId);
  }

  bool _canMutateVisit(VisitDocumentationState current) {
    if (!_canEditVisit(current.visit)) {
      return false;
    }
    if (current.visit.status == VisitStatus.completed && current.workspaceEditMode != WorkspaceEditMode.editing) {
      return false;
    }
    return true;
  }

  /// Whether the visit can be submitted (in-progress only, with edit permission).
  bool canSubmitVisit(VisitDetail visit) => _canEditVisit(visit) && visit.status == VisitStatus.inProgress;

  /// Completes an in-progress visit. Persists local draft fields and keeps documentation editable afterward.
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    final initial = state.value;
    if (initial == null) {
      throw StateError('Visit documentation is not loaded.');
    }
    if (!canSubmitVisit(initial.visit)) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Only in-progress visits with edit permission can be submitted.',
        ),
      );
    }

    if (_canEditVisit(initial.visit)) {
      prepareEncounterReview();

      final afterFlush = state.value ?? initial;
      if (afterFlush.needsPersistBeforeSubmit) {
        final saved = await saveAll();
        if (!saved) {
          final after = state.value ?? afterFlush;
          throw RpcFailure(
            RpcResult(
              success: false,
              errorCode: after.saveStatus == DocumentationSaveStatus.stale ? 'STALE_DOCUMENTATION' : 'INVALID_INPUT',
              errorMessage: after.errorMessage ?? 'Unable to save visit changes before completing.',
            ),
          );
        }
      }
    }

    final current = state.value ?? initial;
    final concurrencyToken = expectedUpdatedAt ?? current.expectedUpdatedAt;

    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .completeVisit(visitId: current.visit.id, expectedUpdatedAt: concurrencyToken);

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
          complaint: current.complaint,
          history: current.history,
          examination: current.examination,
          diagnosis: current.diagnosis,
          plan: current.plan,
          expectedUpdatedAt: refreshed.documentation?.updatedAt ?? refreshed.updatedAt ?? current.expectedUpdatedAt,
          workspaceEditMode: WorkspaceEditMode.viewing,
          noteEditMode: DocumentationEditMode.readOnly,
          saveStatus: DocumentationSaveStatus.saved,
          clearError: true,
        ),
      );
      return result;
    } on RpcFailure {
      rethrow;
    }
  }

  void updateComplaint(String value, {List<dynamic>? richDelta}) =>
      _updateDraft(complaint: value, richSection: ClinicalNoteSection.complaint, richDelta: richDelta);

  void updateHistory(String value, {List<dynamic>? richDelta}) =>
      _updateDraft(history: value, richSection: ClinicalNoteSection.history, richDelta: richDelta);

  void updateExamination(String value, {List<dynamic>? richDelta}) =>
      _updateDraft(examination: value, richSection: ClinicalNoteSection.examination, richDelta: richDelta);

  void updateDiagnosis(String value, {List<dynamic>? richDelta}) =>
      _updateDraft(diagnosis: value, richSection: ClinicalNoteSection.diagnosis, richDelta: richDelta);

  void updatePlan(String value, {List<dynamic>? richDelta}) =>
      _updateDraft(plan: value, richSection: ClinicalNoteSection.plan, richDelta: richDelta);

  void _updateDraft({
    String? complaint,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
    ClinicalNoteSection? richSection,
    List<dynamic>? richDelta,
  }) {
    final current = state.value;
    if (current == null || !_canMutateVisit(current)) {
      return;
    }

    Map<ClinicalNoteSection, List<dynamic>>? nextRichDrafts;
    if (richSection != null) {
      nextRichDrafts = Map<ClinicalNoteSection, List<dynamic>>.from(current.richTextDrafts);
      if (richDelta == null) {
        nextRichDrafts.remove(richSection);
      } else {
        nextRichDrafts[richSection] = richDelta;
      }
    }

    state = AsyncData(
      current.copyWith(
        complaint: complaint,
        history: history,
        examination: examination,
        diagnosis: diagnosis,
        plan: plan,
        richTextDrafts: nextRichDrafts,
        saveStatus: DocumentationSaveStatus.idle,
        clearError: true,
      ),
    );
  }

  /// Persists all local draft fields (clinical note + staged structured data).
  ///
  /// Returns `false` when a save fails or the state is stale; `true` when
  /// everything is persisted (or there was nothing to save).
  Future<bool> saveAll() async {
    prepareEncounterReview();

    final current = state.value;
    if (current == null || !_canMutateVisit(current)) {
      return true;
    }

    if (!current.needsPersistBeforeSubmit) {
      return true;
    }

    state = AsyncData(current.copyWith(saveStatus: DocumentationSaveStatus.saving, clearError: true));

    if (current.hasPendingEncounterDraft) {
      final flushed = await _flushEncounterDraft(current);
      if (!flushed) {
        return false;
      }
    }

    final afterStructured = state.value ?? current;
    if (afterStructured.clinicalNoteDiffersFromPersisted) {
      await save();
      final afterNote = state.value;
      if (afterNote == null ||
          afterNote.saveStatus == DocumentationSaveStatus.error ||
          afterNote.saveStatus == DocumentationSaveStatus.stale) {
        return false;
      }
      return true;
    }

    _settleSaveStatusAfterSuccessfulPersist();
    return true;
  }

  /// Clears a lingering [DocumentationSaveStatus.saving] after structured-only
  /// persistence when no clinical note save runs afterward.
  void _settleSaveStatusAfterSuccessfulPersist() {
    final current = state.value;
    if (current == null || current.saveStatus != DocumentationSaveStatus.saving) {
      return;
    }
    state = AsyncData(current.copyWith(saveStatus: DocumentationSaveStatus.saved));
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (!_canMutateVisit(current)) {
      return;
    }

    final lengthError = clinicalSectionLengthError(
      complaint: current.complaint,
      history: current.history,
      examination: current.examination,
      diagnosis: current.diagnosis,
      plan: current.plan,
    );
    if (lengthError != null) {
      state = AsyncData(current.copyWith(saveStatus: DocumentationSaveStatus.error, errorMessage: lengthError));
      return;
    }

    state = AsyncData(current.copyWith(saveStatus: DocumentationSaveStatus.saving, clearError: true));

    try {
      final saved = await ref
          .read(visitRepositoryProvider)
          .saveVisitDocumentation(
            visitId: current.visit.id,
            expectedUpdatedAt: current.expectedUpdatedAt,
            complaint: _nullableSection(current.complaint),
            history: _nullableSection(current.history),
            examination: _nullableSection(current.examination),
            diagnosis: _nullableSection(current.diagnosis),
            plan: _nullableSection(current.plan),
          );

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
      final next = VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns)
          .copyWith(
            complaint: current.complaint,
            history: current.history,
            examination: current.examination,
            diagnosis: current.diagnosis,
            plan: current.plan,
            expectedUpdatedAt: saved.updatedAt,
            saveStatus: DocumentationSaveStatus.saved,
            workspaceEditMode: current.workspaceEditMode,
            noteEditMode: DocumentationEditMode.readOnly,
          );
      state = AsyncData(next);
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'STALE_DOCUMENTATION') {
        state = AsyncData(
          currentAfter.copyWith(saveStatus: DocumentationSaveStatus.stale, errorMessage: visitMessageForRpc(error)),
        );
        return;
      }
      state = AsyncData(
        currentAfter.copyWith(saveStatus: DocumentationSaveStatus.error, errorMessage: visitMessageForRpc(error)),
      );
    } catch (error) {
      final currentAfter = state.value ?? current;
      state = AsyncData(
        currentAfter.copyWith(saveStatus: DocumentationSaveStatus.error, errorMessage: error.toString()),
      );
    }
  }

  void enterEditMode() {
    final current = state.value;
    if (current == null || !_canEditVisit(current.visit)) return;
    state = AsyncData(current.copyWith(noteEditMode: DocumentationEditMode.editing));
  }

  /// Enables editing across the encounter workspace (required for completed visits).
  void enterWorkspaceEditMode() {
    final current = state.value;
    if (current == null || !_canEditVisit(current.visit)) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        workspaceEditMode: WorkspaceEditMode.editing,
        noteEditMode: DocumentationEditMode.editing,
        clearError: true,
      ),
    );
  }

  /// Refreshes visit metadata without discarding unsaved clinical note draft.
  Future<void> refreshVisitPreservingDraft() async {
    final current = state.value;
    if (current == null) {
      return;
    }

    final repo = ref.read(visitRepositoryProvider);
    final refreshed = await repo.getVisit(visitId: current.visit.id);
    final predefinedVitalSigns = await repo.listPredefinedVitalSigns();
    final mergedVisit = current.encounterDraft.applyTo(refreshed);
    state = AsyncData(
      current.copyWith(
        visit: mergedVisit,
        persistedVisit: refreshed,
        predefinedVitalSigns: predefinedVitalSigns,
        workspaceEditMode: current.workspaceEditMode,
      ),
    );
  }

  void _applyEncounterDraft(VisitEncounterDraft draft) {
    final current = state.value;
    if (current == null || !_canMutateVisit(current)) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        encounterDraft: draft,
        visit: draft.applyTo(current.persistedVisit),
        saveStatus: DocumentationSaveStatus.idle,
        clearError: true,
      ),
    );
  }

  void registerClinicalNoteFlush(VoidCallback callback) {
    _clinicalNoteFlushCallbacks.add(callback);
  }

  void unregisterClinicalNoteFlush(VoidCallback callback) {
    _clinicalNoteFlushCallbacks.remove(callback);
  }

  void _flushClinicalNoteDrafts() {
    for (final callback in _clinicalNoteFlushCallbacks) {
      callback();
    }
  }

  /// Pulls cached editor and staged draft input into state before Summary or submit validation.
  ///
  /// Sync-only: does not persist. Call before evaluating submit readiness so Quill
  /// controller content and structured draft overlays are reflected in state.
  VisitDocumentationState? prepareEncounterReview() {
    _flushClinicalNoteDrafts();
    final current = state.value;
    if (current == null) {
      return null;
    }

    final syncedPlainText = _syncPlainTextFromRichDrafts(current);

    // Recover from a prior structured-only save that left saveStatus stuck on saving.
    final saveStatus = syncedPlainText.saveStatus == DocumentationSaveStatus.saving
        ? DocumentationSaveStatus.idle
        : syncedPlainText.saveStatus;

    final synced = syncedPlainText.copyWith(visit: syncedPlainText.effectiveVisit, saveStatus: saveStatus);
    state = AsyncData(synced);
    return synced;
  }

  VisitDocumentationState _syncPlainTextFromRichDrafts(VisitDocumentationState current) {
    String syncSection(String plain, ClinicalNoteSection section) {
      if (plain.trim().isNotEmpty) {
        return plain;
      }
      return plainTextFromRichDelta(current.richTextDrafts[section]);
    }

    return current.copyWith(
      complaint: syncSection(current.complaint, ClinicalNoteSection.complaint),
      history: syncSection(current.history, ClinicalNoteSection.history),
      examination: syncSection(current.examination, ClinicalNoteSection.examination),
      diagnosis: syncSection(current.diagnosis, ClinicalNoteSection.diagnosis),
      plan: syncSection(current.plan, ClinicalNoteSection.plan),
    );
  }

  VisitVitalSign? _findVitalSign(String id) {
    final current = state.value;
    if (current == null) return null;
    for (final sign in current.visit.vitalSigns) {
      if (sign.id == id) return sign;
    }
    return null;
  }

  VisitInvestigation? _findInvestigation(String id) {
    final current = state.value;
    if (current == null) return null;
    for (final item in [...current.visit.investigations, ...current.visit.pendingInvestigations]) {
      if (item.id == id) return item;
    }
    return null;
  }

  TreatmentPlanItem? _findTreatmentPlan(String id) {
    final current = state.value;
    if (current == null) return null;
    for (final plan in current.visit.treatmentPlans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  void stageCreateVitalSign({
    required String name,
    required String value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    final current = state.value;
    if (current == null) return;
    final sign = VisitVitalSign(
      id: newVisitDraftId(),
      name: name,
      value: value,
      unit: unit,
      predefinedVitalSignId: predefinedVitalSignId,
    );
    _applyEncounterDraft(
      current.encounterDraft.copyWith(pendingVitalSigns: [...current.encounterDraft.pendingVitalSigns, sign]),
    );
  }

  void stageUpdateVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(vitalSignId)) {
      final updated = draft.pendingVitalSigns
          .map(
            (sign) => sign.id == vitalSignId
                ? VisitVitalSign(
                    id: sign.id,
                    name: name ?? sign.name,
                    value: value ?? sign.value,
                    unit: unit ?? sign.unit,
                    predefinedVitalSignId: predefinedVitalSignId ?? sign.predefinedVitalSignId,
                  )
                : sign,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(pendingVitalSigns: updated));
      return;
    }
    final existing = _findVitalSign(vitalSignId);
    if (existing == null) return;
    final updated = VisitVitalSign(
      id: existing.id,
      name: name ?? existing.name,
      value: value ?? existing.value,
      unit: unit ?? existing.unit,
      predefinedVitalSignId: predefinedVitalSignId ?? existing.predefinedVitalSignId,
    );
    _applyEncounterDraft(draft.copyWith(vitalSignUpdates: {...draft.vitalSignUpdates, vitalSignId: updated}));
  }

  void stageArchiveVitalSign(String vitalSignId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(vitalSignId)) {
      _applyEncounterDraft(
        draft.copyWith(pendingVitalSigns: draft.pendingVitalSigns.where((sign) => sign.id != vitalSignId).toList()),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        archivedVitalSignIds: {...draft.archivedVitalSignIds, vitalSignId},
        vitalSignUpdates: Map<String, VisitVitalSign>.from(draft.vitalSignUpdates)..remove(vitalSignId),
      ),
    );
  }

  void stageCreateInvestigation({required String name, String? note, String? investigationId}) {
    final current = state.value;
    if (current == null) return;
    final investigation = VisitInvestigation(
      id: newVisitDraftId(),
      name: name,
      note: note,
      investigationId: investigationId,
    );
    _applyEncounterDraft(
      current.encounterDraft.copyWith(
        pendingInvestigations: [...current.encounterDraft.pendingInvestigations, investigation],
      ),
    );
  }

  void stageUpdateInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
  }) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(investigationLineId)) {
      final updated = draft.pendingInvestigations
          .map(
            (item) => item.id == investigationLineId
                ? VisitInvestigation(
                    id: item.id,
                    name: name ?? item.name,
                    note: note ?? item.note,
                    investigationId: investigationId ?? item.investigationId,
                  )
                : item,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(pendingInvestigations: updated));
      return;
    }
    final existing = _findInvestigation(investigationLineId);
    if (existing == null) return;
    final updated = VisitInvestigation(
      id: existing.id,
      name: name ?? existing.name,
      note: note ?? existing.note,
      investigationId: investigationId ?? existing.investigationId,
      result: existing.result,
      resultRecordedAt: existing.resultRecordedAt,
      orderedVisitId: existing.orderedVisitId,
      orderedVisitDate: existing.orderedVisitDate,
    );
    _applyEncounterDraft(
      draft.copyWith(investigationUpdates: {...draft.investigationUpdates, investigationLineId: updated}),
    );
  }

  void stageArchiveInvestigation(String investigationLineId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(investigationLineId)) {
      _applyEncounterDraft(
        draft.copyWith(
          pendingInvestigations: draft.pendingInvestigations.where((item) => item.id != investigationLineId).toList(),
        ),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        archivedInvestigationIds: {...draft.archivedInvestigationIds, investigationLineId},
        investigationUpdates: Map<String, VisitInvestigation>.from(draft.investigationUpdates)
          ..remove(investigationLineId),
      ),
    );
  }

  void stageInvestigationResult({required String investigationLineId, required String result}) {
    final current = state.value;
    if (current == null) return;
    _applyEncounterDraft(
      current.encounterDraft.copyWith(
        investigationResults: {...current.encounterDraft.investigationResults, investigationLineId: result.trim()},
      ),
    );
  }

  void stageCreateTreatmentPlan({
    required String medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) {
    final current = state.value;
    if (current == null) return;
    final plan = TreatmentPlanItem(
      id: newVisitDraftId(),
      visitId: current.visit.id,
      patientId: current.visit.patientId,
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
    _applyEncounterDraft(
      current.encounterDraft.copyWith(pendingTreatmentPlans: [...current.encounterDraft.pendingTreatmentPlans, plan]),
    );
  }

  void stageUpdateTreatmentPlan({
    required String treatmentPlanId,
    String? medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(treatmentPlanId)) {
      final updated = draft.pendingTreatmentPlans
          .map(
            (plan) => plan.id == treatmentPlanId
                ? plan.copyWith(
                    medicationName: medicationName,
                    medicationId: medicationId,
                    dosage: dosage,
                    frequency: frequency,
                    duration: duration,
                    notes: notes,
                  )
                : plan,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(pendingTreatmentPlans: updated));
      return;
    }
    final existing = _findTreatmentPlan(treatmentPlanId);
    if (existing == null) return;
    final updated = existing.copyWith(
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
    _applyEncounterDraft(
      draft.copyWith(treatmentPlanUpdates: {...draft.treatmentPlanUpdates, treatmentPlanId: updated}),
    );
  }

  void stageArchiveTreatmentPlan(String treatmentPlanId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(treatmentPlanId)) {
      _applyEncounterDraft(
        draft.copyWith(
          pendingTreatmentPlans: draft.pendingTreatmentPlans.where((plan) => plan.id != treatmentPlanId).toList(),
        ),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        archivedTreatmentPlanIds: {...draft.archivedTreatmentPlanIds, treatmentPlanId},
        treatmentPlanUpdates: Map<String, TreatmentPlanItem>.from(draft.treatmentPlanUpdates)..remove(treatmentPlanId),
      ),
    );
  }

  void stageAttachment({
    required VisitAttachmentPickInput pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  }) {
    final current = state.value;
    if (current == null) return;
    final fileType = VisitAttachmentService.inferFileTypeFromFilename(pick.filename);
    if (fileType == null) return;
    final pending = PendingVisitAttachment(
      id: newVisitDraftId(),
      pick: pick,
      label: label,
      fileType: fileType,
      uploadedBy: uploadedBy,
      uploadedByName: uploadedByName,
    );
    _applyEncounterDraft(
      current.encounterDraft.copyWith(pendingAttachments: [...current.encounterDraft.pendingAttachments, pending]),
    );
  }

  void stageDeleteAttachment(String attachmentId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    if (isVisitDraftId(attachmentId)) {
      _applyEncounterDraft(
        draft.copyWith(pendingAttachments: draft.pendingAttachments.where((item) => item.id != attachmentId).toList()),
      );
      return;
    }
    _applyEncounterDraft(draft.copyWith(deletedAttachmentIds: {...draft.deletedAttachmentIds, attachmentId}));
  }

  void stageCreateAllergy({required String substance, String? reaction}) {
    final current = state.value;
    if (current == null) return;
    final allergy = PatientAllergy(id: newVisitDraftId(), substance: substance, reaction: reaction);
    final safety = current.encounterDraft.patientSafety;
    _applyEncounterDraft(
      current.encounterDraft.copyWith(
        patientSafety: safety.copyWith(pendingAllergies: [...safety.pendingAllergies, allergy]),
      ),
    );
  }

  void stageUpdateAllergy({required String allergyId, String? substance, String? reaction}) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(allergyId)) {
      final updated = safety.pendingAllergies
          .map(
            (allergy) => allergy.id == allergyId
                ? PatientAllergy(
                    id: allergy.id,
                    substance: substance ?? allergy.substance,
                    reaction: reaction ?? allergy.reaction,
                  )
                : allergy,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(patientSafety: safety.copyWith(pendingAllergies: updated)));
      return;
    }
    final existing = _findAllergyInContext(allergyId, current);
    if (existing == null && substance == null) return;
    final updated = PatientAllergy(
      id: allergyId,
      substance: substance ?? existing?.substance ?? '',
      reaction: reaction ?? existing?.reaction,
    );
    _applyEncounterDraft(
      draft.copyWith(patientSafety: safety.copyWith(allergyUpdates: {...safety.allergyUpdates, allergyId: updated})),
    );
  }

  void stageArchiveAllergy(String allergyId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(allergyId)) {
      _applyEncounterDraft(
        draft.copyWith(
          patientSafety: safety.copyWith(
            pendingAllergies: safety.pendingAllergies.where((allergy) => allergy.id != allergyId).toList(),
          ),
        ),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        patientSafety: safety.copyWith(
          archivedAllergyIds: {...safety.archivedAllergyIds, allergyId},
          allergyUpdates: Map<String, PatientAllergy>.from(safety.allergyUpdates)..remove(allergyId),
        ),
      ),
    );
  }

  void stageCreateMedication({required String name, String? medicationId, String? note}) {
    final current = state.value;
    if (current == null) return;
    final med = PatientMedication(id: newVisitDraftId(), name: name, medicationId: medicationId, note: note);
    final safety = current.encounterDraft.patientSafety;
    _applyEncounterDraft(
      current.encounterDraft.copyWith(
        patientSafety: safety.copyWith(pendingMedications: [...safety.pendingMedications, med]),
      ),
    );
  }

  void stageUpdateMedication({required String medicationRecordId, String? name, String? medicationId, String? note}) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(medicationRecordId)) {
      final updated = safety.pendingMedications
          .map(
            (med) => med.id == medicationRecordId
                ? PatientMedication(
                    id: med.id,
                    name: name ?? med.name,
                    medicationId: medicationId ?? med.medicationId,
                    note: note ?? med.note,
                  )
                : med,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(patientSafety: safety.copyWith(pendingMedications: updated)));
      return;
    }
    final existing = _findMedicationInContext(medicationRecordId, current);
    if (existing == null && name == null) return;
    final updated = PatientMedication(
      id: medicationRecordId,
      name: name ?? existing?.name ?? '',
      medicationId: medicationId ?? existing?.medicationId,
      note: note ?? existing?.note,
    );
    _applyEncounterDraft(
      draft.copyWith(
        patientSafety: safety.copyWith(medicationUpdates: {...safety.medicationUpdates, medicationRecordId: updated}),
      ),
    );
  }

  void stageArchiveMedication(String medicationRecordId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(medicationRecordId)) {
      _applyEncounterDraft(
        draft.copyWith(
          patientSafety: safety.copyWith(
            pendingMedications: safety.pendingMedications.where((med) => med.id != medicationRecordId).toList(),
          ),
        ),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        patientSafety: safety.copyWith(
          archivedMedicationIds: {...safety.archivedMedicationIds, medicationRecordId},
          medicationUpdates: Map<String, PatientMedication>.from(safety.medicationUpdates)..remove(medicationRecordId),
        ),
      ),
    );
  }

  void stageCreateCondition({required String name, String? note}) {
    final current = state.value;
    if (current == null) return;
    final condition = PatientChronicCondition(id: newVisitDraftId(), name: name, note: note);
    final safety = current.encounterDraft.patientSafety;
    _applyEncounterDraft(
      current.encounterDraft.copyWith(
        patientSafety: safety.copyWith(pendingConditions: [...safety.pendingConditions, condition]),
      ),
    );
  }

  void stageUpdateCondition({required String conditionId, String? name, String? note}) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(conditionId)) {
      final updated = safety.pendingConditions
          .map(
            (condition) => condition.id == conditionId
                ? PatientChronicCondition(id: condition.id, name: name ?? condition.name, note: note ?? condition.note)
                : condition,
          )
          .toList(growable: false);
      _applyEncounterDraft(draft.copyWith(patientSafety: safety.copyWith(pendingConditions: updated)));
      return;
    }
    final existing = _findConditionInContext(conditionId, current);
    if (existing == null && name == null) return;
    final updated = PatientChronicCondition(
      id: conditionId,
      name: name ?? existing?.name ?? '',
      note: note ?? existing?.note,
    );
    _applyEncounterDraft(
      draft.copyWith(
        patientSafety: safety.copyWith(conditionUpdates: {...safety.conditionUpdates, conditionId: updated}),
      ),
    );
  }

  void stageArchiveCondition(String conditionId) {
    final current = state.value;
    if (current == null) return;
    final draft = current.encounterDraft;
    final safety = draft.patientSafety;
    if (isVisitDraftId(conditionId)) {
      _applyEncounterDraft(
        draft.copyWith(
          patientSafety: safety.copyWith(
            pendingConditions: safety.pendingConditions.where((condition) => condition.id != conditionId).toList(),
          ),
        ),
      );
      return;
    }
    _applyEncounterDraft(
      draft.copyWith(
        patientSafety: safety.copyWith(
          archivedConditionIds: {...safety.archivedConditionIds, conditionId},
          conditionUpdates: Map<String, PatientChronicCondition>.from(safety.conditionUpdates)..remove(conditionId),
        ),
      ),
    );
  }

  PatientAllergy? _findAllergyInContext(String id, VisitDocumentationState current) {
    for (final allergy in current.encounterDraft.patientSafety.pendingAllergies) {
      if (allergy.id == id) return allergy;
    }
    return null;
  }

  PatientMedication? _findMedicationInContext(String id, VisitDocumentationState current) {
    for (final med in current.encounterDraft.patientSafety.pendingMedications) {
      if (med.id == id) return med;
    }
    return null;
  }

  PatientChronicCondition? _findConditionInContext(String id, VisitDocumentationState current) {
    for (final condition in current.encounterDraft.patientSafety.pendingConditions) {
      if (condition.id == id) return condition;
    }
    return null;
  }

  Future<bool> _flushEncounterDraft(VisitDocumentationState current) async {
    final repo = ref.read(visitRepositoryProvider);
    final attachmentService = ref.read(visitAttachmentServiceProvider);
    final draft = current.encounterDraft;
    final orgId = ref.read(authSessionProvider).context?.organizationId?.trim();

    try {
      for (final id in draft.archivedVitalSignIds) {
        if (!isVisitDraftId(id)) {
          await repo.archiveVisitVitalSign(vitalSignId: id);
        }
      }
      for (final sign in draft.pendingVitalSigns) {
        await repo.createVisitVitalSign(
          visitId: current.visit.id,
          name: sign.name,
          value: sign.value,
          unit: sign.unit,
          predefinedVitalSignId: sign.predefinedVitalSignId,
        );
      }
      for (final entry in draft.vitalSignUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updateVisitVitalSign(
            vitalSignId: entry.key,
            name: entry.value.name,
            value: entry.value.value,
            unit: entry.value.unit,
            predefinedVitalSignId: entry.value.predefinedVitalSignId,
          );
        }
      }

      for (final id in draft.archivedInvestigationIds) {
        if (!isVisitDraftId(id)) {
          await repo.archiveVisitInvestigation(investigationLineId: id);
        }
      }
      for (final investigation in draft.pendingInvestigations) {
        await repo.createVisitInvestigation(
          visitId: current.visit.id,
          name: investigation.name,
          note: investigation.note,
          investigationId: investigation.investigationId,
        );
      }
      for (final entry in draft.investigationUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updateVisitInvestigation(
            investigationLineId: entry.key,
            name: entry.value.name,
            note: entry.value.note,
            investigationId: entry.value.investigationId,
          );
        }
      }
      for (final entry in draft.investigationResults.entries) {
        await repo.recordInvestigationResult(investigationLineId: entry.key, result: entry.value);
      }

      for (final id in draft.archivedTreatmentPlanIds) {
        if (!isVisitDraftId(id)) {
          await repo.archiveTreatmentPlan(treatmentPlanId: id);
        }
      }
      for (final plan in draft.pendingTreatmentPlans) {
        await repo.createTreatmentPlan(
          visitId: current.visit.id,
          medicationName: plan.medicationName,
          medicationId: plan.medicationId,
          dosage: plan.dosage ?? '',
          frequency: plan.frequency ?? '',
          duration: plan.duration ?? '',
          notes: plan.notes,
        );
      }
      for (final entry in draft.treatmentPlanUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updateTreatmentPlan(
            treatmentPlanId: entry.key,
            medicationName: entry.value.medicationName,
            medicationId: entry.value.medicationId,
            dosage: entry.value.dosage,
            frequency: entry.value.frequency,
            duration: entry.value.duration,
            notes: entry.value.notes,
          );
        }
      }

      if (orgId != null && orgId.isNotEmpty) {
        for (final pending in draft.pendingAttachments) {
          await attachmentService.uploadAndRegister(
            organizationId: orgId,
            branchId: current.visit.branchId,
            visitId: current.visit.id,
            pick: pending.pick,
            label: pending.label,
          );
        }
      }
      for (final id in draft.deletedAttachmentIds) {
        if (!isVisitDraftId(id)) {
          await repo.deleteVisitAttachment(attachmentId: id);
        }
      }

      final safety = draft.patientSafety;
      final patientId = current.visit.patientId;
      for (final id in safety.archivedAllergyIds) {
        if (!isVisitDraftId(id)) await repo.archivePatientAllergy(allergyId: id);
      }
      for (final allergy in safety.pendingAllergies) {
        await repo.createPatientAllergy(patientId: patientId, substance: allergy.substance, reaction: allergy.reaction);
      }
      for (final entry in safety.allergyUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updatePatientAllergy(
            allergyId: entry.key,
            substance: entry.value.substance,
            reaction: entry.value.reaction,
          );
        }
      }

      for (final id in safety.archivedMedicationIds) {
        if (!isVisitDraftId(id)) await repo.archivePatientMedication(medicationRecordId: id);
      }
      for (final med in safety.pendingMedications) {
        await repo.createPatientMedication(
          patientId: patientId,
          name: med.name,
          medicationId: med.medicationId,
          note: med.note,
        );
      }
      for (final entry in safety.medicationUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updatePatientMedication(
            medicationRecordId: entry.key,
            name: entry.value.name,
            medicationId: entry.value.medicationId,
            note: entry.value.note,
          );
        }
      }

      for (final id in safety.archivedConditionIds) {
        if (!isVisitDraftId(id)) await repo.archivePatientChronicCondition(conditionId: id);
      }
      for (final condition in safety.pendingConditions) {
        await repo.createPatientChronicCondition(patientId: patientId, name: condition.name, note: condition.note);
      }
      for (final entry in safety.conditionUpdates.entries) {
        if (!isVisitDraftId(entry.key)) {
          await repo.updatePatientChronicCondition(
            conditionId: entry.key,
            name: entry.value.name,
            note: entry.value.note,
          );
        }
      }

      final refreshed = await repo.getVisit(visitId: current.visit.id);
      final predefinedVitalSigns = current.predefinedVitalSigns;
      final afterNote = state.value ?? current;
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: predefinedVitalSigns).copyWith(
          complaint: afterNote.complaint,
          history: afterNote.history,
          examination: afterNote.examination,
          diagnosis: afterNote.diagnosis,
          plan: afterNote.plan,
          richTextDrafts: afterNote.richTextDrafts,
          expectedUpdatedAt: afterNote.expectedUpdatedAt,
          noteEditMode: afterNote.noteEditMode,
          saveStatus: afterNote.saveStatus,
        ),
      );
      return true;
    } on RpcFailure catch (error) {
      await _recoverEncounterDraftAfterFlushFailure(current);
      final currentAfter = state.value ?? current;
      final baseMessage = visitMessageForRpc(error);
      state = AsyncData(
        currentAfter.copyWith(
          saveStatus: DocumentationSaveStatus.error,
          errorMessage: '$baseMessage Some changes may have been saved — review the visit before retrying.',
        ),
      );
      return false;
    } catch (error) {
      await _recoverEncounterDraftAfterFlushFailure(current);
      final currentAfter = state.value ?? current;
      state = AsyncData(
        currentAfter.copyWith(
          saveStatus: DocumentationSaveStatus.error,
          errorMessage: '${error.toString()} Some changes may have been saved — review the visit before retrying.',
        ),
      );
      return false;
    }
  }

  /// Reloads persisted visit rows after a partial structured flush so the UI matches the server.
  ///
  /// Clears the encounter draft overlay to avoid duplicate creates on retry.
  Future<void> _recoverEncounterDraftAfterFlushFailure(VisitDocumentationState current) async {
    try {
      final repo = ref.read(visitRepositoryProvider);
      final refreshed = await repo.getVisit(visitId: current.visit.id);
      final afterNote = state.value ?? current;
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
          complaint: afterNote.complaint,
          history: afterNote.history,
          examination: afterNote.examination,
          diagnosis: afterNote.diagnosis,
          plan: afterNote.plan,
          richTextDrafts: afterNote.richTextDrafts,
          expectedUpdatedAt: refreshed.documentation?.updatedAt ?? refreshed.updatedAt ?? afterNote.expectedUpdatedAt,
          noteEditMode: afterNote.noteEditMode,
          workspaceEditMode: afterNote.workspaceEditMode,
          encounterDraft: const VisitEncounterDraft(),
          saveStatus: DocumentationSaveStatus.error,
        ),
      );
    } catch (_) {
      // Keep the pre-recovery state when refresh fails.
    }
  }

  Future<void> reloadVisit() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> reloadAfterStale() async {
    ref.invalidateSelf();
    await future;
  }

  String? _nullableSection(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
