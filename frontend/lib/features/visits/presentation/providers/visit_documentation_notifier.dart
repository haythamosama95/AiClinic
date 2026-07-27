import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';
import 'package:ai_clinic/features/appointments/application/appointment_surface_invalidation.dart';
import 'package:ai_clinic/features/visits/application/visit_encounter_flusher.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_pick.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_attachments_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_clinical_data_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_state.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_patient_safety_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_workspace_permissions.dart';

export 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_state.dart';

final visitDocumentationProvider = AsyncNotifierProvider.family<VisitDocumentationNotifier, VisitDocumentationState, String>(
  VisitDocumentationNotifier.new,
);

/// Coordinates saving notes and all encounter draft sub-notifiers.
final visitSaveAllProvider = Provider.family<Future<bool> Function(), String>((ref, visitId) {
  return () => ref.read(visitDocumentationProvider(visitId).notifier).saveAll();
});

/// Family arg is injected by [visitDocumentationProvider] via `NotifierT Function(String)`.
class VisitDocumentationNotifier extends AsyncNotifier<VisitDocumentationState> {
  VisitDocumentationNotifier(this._visitId);

  final String _visitId;
  final Set<VoidCallback> _clinicalNoteFlushCallbacks = {};

  @override
  Future<VisitDocumentationState> build() async {
    ref.listen(visitClinicalDataProvider(_visitId), (_, _) => syncEncounterDraftFromSubNotifiers());
    ref.listen(visitAttachmentsProvider(_visitId), (_, _) => syncEncounterDraftFromSubNotifiers());
    ref.listen(visitPatientSafetyProvider(_visitId), (_, _) => syncEncounterDraftFromSubNotifiers());
    final loaded = await _load();
    ref.read(visitClinicalDataProvider(_visitId).notifier).setPersistedVisit(loaded.persistedVisit);
    await ref.read(visitPatientSafetyProvider(_visitId).notifier).ensureLoaded(loaded.persistedVisit.patientId);
    return loaded;
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

  bool canMutateWorkspace(VisitDocumentationState current) => canMutateVisitWorkspace(ref, _visitId, current);

  bool _canEditVisit(VisitDetail visit) {
    final permissions = ref.read(permissionServiceProvider);
    final branchIds = ref.read(authSessionProvider).context?.branchIds ?? const <String>[];
    return permissions.canEditVisitSoap() && branchIds.contains(visit.branchId);
  }

  bool _canMutateVisit(VisitDocumentationState current) => canMutateWorkspace(current);

  /// Whether the visit can be submitted (in-progress only, with edit permission).
  bool canSubmitVisit(VisitDetail visit) => _canEditVisit(visit) && visit.status == VisitStatus.inProgress;

  VisitEncounterDraft _composeEncounterDraft() {
    final clinical = ref.read(visitClinicalDataProvider(_visitId));
    final attachments = ref.read(visitAttachmentsProvider(_visitId));
    final safetyDraft = ref.read(visitPatientSafetyProvider(_visitId)).value?.safetyDraft ?? const PatientSafetyDraft();
    return VisitEncounterDraft(
      pendingVitalSigns: clinical.pendingVitalSigns,
      vitalSignUpdates: clinical.vitalSignUpdates,
      archivedVitalSignIds: clinical.archivedVitalSignIds,
      pendingInvestigations: clinical.pendingInvestigations,
      investigationUpdates: clinical.investigationUpdates,
      archivedInvestigationIds: clinical.archivedInvestigationIds,
      pendingTreatmentPlans: clinical.pendingTreatmentPlans,
      treatmentPlanUpdates: clinical.treatmentPlanUpdates,
      archivedTreatmentPlanIds: clinical.archivedTreatmentPlanIds,
      investigationResults: clinical.investigationResults,
      pendingAttachments: attachments.pendingAttachments,
      deletedAttachmentIds: attachments.deletedAttachmentIds,
      patientSafety: safetyDraft,
    );
  }

  void syncEncounterDraftFromSubNotifiers() {
    final current = state.value;
    if (current == null) return;
    final composed = _composeEncounterDraft();
    if (composed == current.encounterDraft) return;
    state = AsyncData(current.copyWith(encounterDraft: composed));
  }

  void _applyComposedDraft(VisitEncounterDraft draft) {
    ref.read(visitClinicalDataProvider(_visitId).notifier).replaceFromEncounterDraft(draft);
    ref.read(visitAttachmentsProvider(_visitId).notifier).replaceFromEncounterDraft(draft);
    ref.read(visitPatientSafetyProvider(_visitId).notifier).replaceSafetyDraft(draft.patientSafety);
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(encounterDraft: draft));
    }
  }

  /// Clears pending encounter drafts and resets clinical notes to persisted values.
  void clearPendingDrafts() {
    final current = state.value;
    if (current == null) return;

    final persisted = current.persistedVisit.documentation;
    ref.read(visitClinicalDataProvider(_visitId).notifier).clearDraft();
    ref.read(visitAttachmentsProvider(_visitId).notifier).clearDraft();
    ref.read(visitPatientSafetyProvider(_visitId).notifier).clearDraft();

    state = AsyncData(
      current.copyWith(
        complaint: persisted?.complaint ?? '',
        history: persisted?.history ?? '',
        examination: persisted?.examination ?? '',
        diagnosis: persisted?.diagnosis ?? '',
        plan: persisted?.plan ?? '',
        richTextDrafts: const {},
        encounterDraft: const VisitEncounterDraft(),
        saveStatus: DocumentationSaveStatus.idle,
        clearError: true,
        clearStaleConflict: true,
      ),
    );
  }

  /// Disposes visit-scoped providers after finalization so drafts do not leak across visits.
  void disposeAfterFinalize() {
    ref.invalidate(visitDocumentationProvider(_visitId));
    ref.invalidate(visitClinicalDataProvider(_visitId));
    ref.invalidate(visitAttachmentsProvider(_visitId));
    ref.invalidate(visitPatientSafetyProvider(_visitId));
  }

  /// Refreshes the concurrency token after a stale conflict.
  Future<void> resolveStaleConflict({required bool keepLocalDraft}) async {
    final current = state.value;
    if (current == null) return;

    final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.persistedVisit.id);
    final newToken = refreshed.documentation?.updatedAt ?? refreshed.updatedAt ?? current.expectedUpdatedAt;

    if (keepLocalDraft) {
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
          complaint: current.complaint,
          history: current.history,
          examination: current.examination,
          diagnosis: current.diagnosis,
          plan: current.plan,
          richTextDrafts: current.richTextDrafts,
          expectedUpdatedAt: newToken,
          encounterDraft: current.encounterDraft,
          workspaceEditMode: current.workspaceEditMode,
          noteEditMode: current.noteEditMode,
          saveStatus: DocumentationSaveStatus.idle,
          clearError: true,
          clearStaleConflict: true,
        ),
      );
      _applyComposedDraft(current.encounterDraft);
      return;
    }

    ref.read(visitClinicalDataProvider(_visitId).notifier).clearDraft();
    ref.read(visitAttachmentsProvider(_visitId).notifier).clearDraft();
    ref.read(visitPatientSafetyProvider(_visitId).notifier).clearDraft();
    state = AsyncData(
      VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
        expectedUpdatedAt: newToken,
        workspaceEditMode: current.workspaceEditMode,
        saveStatus: DocumentationSaveStatus.idle,
        clearError: true,
        clearStaleConflict: true,
      ),
    );
  }

  /// Completes an in-progress visit. Persists local draft fields and keeps documentation editable afterward.
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    final initial = state.value;
    if (initial == null) {
      throw StateError('Visit documentation is not loaded.');
    }
    if (initial.saveStatus == DocumentationSaveStatus.stale) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'STALE_DOCUMENTATION',
          errorMessage: initial.errorMessage ?? 'Resolve the documentation conflict before completing the visit.',
        ),
      );
    }
    if (!canSubmitVisit(initial.persistedVisit)) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Only in-progress visits with edit permission can be submitted.',
        ),
      );
    }

    if (_canEditVisit(initial.persistedVisit)) {
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
    if (current.saveStatus == DocumentationSaveStatus.stale) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'STALE_DOCUMENTATION',
          errorMessage: current.errorMessage ?? 'Resolve the documentation conflict before completing the visit.',
        ),
      );
    }

    final concurrencyToken = current.expectedUpdatedAt;

    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .completeVisit(visitId: current.persistedVisit.id, expectedUpdatedAt: concurrencyToken);

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.persistedVisit.id);
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
          workspaceEditMode: WorkspaceEditMode.viewing,
          noteEditMode: DocumentationEditMode.readOnly,
          saveStatus: DocumentationSaveStatus.saved,
          clearError: true,
        ),
      );
      invalidateAppointmentAfterVisitCompleted(ref, appointmentId: result.appointmentId);
      disposeAfterFinalize();
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
        clearStaleConflict: true,
      ),
    );
  }

  /// Persists all local draft fields (clinical note + staged structured data).
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

    syncEncounterDraftFromSubNotifiers();
    final withDraft = state.value ?? current;
    if (withDraft.hasPendingEncounterDraft) {
      final flushed = await _flushEncounterDraft(withDraft);
      if (!flushed) {
        return false;
      }
    }

    final afterStructured = state.value ?? withDraft;
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

  void _settleSaveStatusAfterSuccessfulPersist() {
    final current = state.value;
    if (current == null || current.saveStatus != DocumentationSaveStatus.saving) {
      return;
    }
    state = AsyncData(current.copyWith(saveStatus: DocumentationSaveStatus.saved, clearStaleConflict: true));
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
      final saved = await ref.read(visitRepositoryProvider).saveVisitDocumentation(
            visitId: current.persistedVisit.id,
            expectedUpdatedAt: current.expectedUpdatedAt,
            complaint: _nullableSection(current.complaint),
            history: _nullableSection(current.history),
            examination: _nullableSection(current.examination),
            diagnosis: _nullableSection(current.diagnosis),
            plan: _nullableSection(current.plan),
          );

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.persistedVisit.id);
      final next = VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
        complaint: current.complaint,
        history: current.history,
        examination: current.examination,
        diagnosis: current.diagnosis,
        plan: current.plan,
        expectedUpdatedAt: saved.updatedAt,
        encounterDraft: current.encounterDraft,
        saveStatus: DocumentationSaveStatus.saved,
        workspaceEditMode: current.workspaceEditMode,
        noteEditMode: DocumentationEditMode.readOnly,
        clearStaleConflict: true,
      );
      state = AsyncData(next);
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'STALE_DOCUMENTATION') {
        final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.persistedVisit.id);
        final serverNote = refreshed.documentation;
        final staleToken = serverNote?.updatedAt ?? refreshed.updatedAt;
        state = AsyncData(
          currentAfter.copyWith(
            saveStatus: DocumentationSaveStatus.stale,
            errorMessage: visitMessageForRpc(error),
            conflictingServerNote: serverNote,
            staleServerUpdatedAt: staleToken,
          ),
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
    if (current == null || !_canEditVisit(current.persistedVisit)) return;
    state = AsyncData(current.copyWith(noteEditMode: DocumentationEditMode.editing));
  }

  void enterWorkspaceEditMode() {
    final current = state.value;
    if (current == null || !_canEditVisit(current.persistedVisit)) {
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

  Future<void> refreshVisitPreservingDraft() async {
    final current = state.value;
    if (current == null) {
      return;
    }

    final repo = ref.read(visitRepositoryProvider);
    final refreshed = await repo.getVisit(visitId: current.persistedVisit.id);
    final predefinedVitalSigns = await repo.listPredefinedVitalSigns();
    state = AsyncData(
      current.copyWith(
        persistedVisit: refreshed,
        predefinedVitalSigns: predefinedVitalSigns,
        workspaceEditMode: current.workspaceEditMode,
        encounterDraft: current.encounterDraft,
      ),
    );
    syncEncounterDraftFromSubNotifiers();
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

  VisitDocumentationState? prepareEncounterReview() {
    _flushClinicalNoteDrafts();
    final current = state.value;
    if (current == null) {
      return null;
    }

    syncEncounterDraftFromSubNotifiers();
    final synced = state.value ?? current;
    final syncedPlainText = _syncPlainTextFromRichDrafts(synced);

    final saveStatus = syncedPlainText.saveStatus == DocumentationSaveStatus.saving
        ? DocumentationSaveStatus.idle
        : syncedPlainText.saveStatus;

    final next = syncedPlainText.copyWith(saveStatus: saveStatus);
    state = AsyncData(next);
    return next;
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

  Future<bool> _flushEncounterDraft(VisitDocumentationState current) async {
    final repo = ref.read(visitRepositoryProvider);
    final attachmentService = ref.read(visitAttachmentServiceProvider);
    final orgId = ref.read(authSessionProvider).context?.organizationId?.trim();
    final flusher = VisitEncounterFlusher(repository: repo, attachmentService: attachmentService);
    final initialDraft = _composeEncounterDraft();

    final result = await flusher.flush(
      visit: current.effectiveVisit,
      persistedVisit: current.persistedVisit,
      organizationId: orgId,
      initialDraft: initialDraft,
      onDraftUpdated: _applyComposedDraft,
    );

    if (!result.success) {
      await _recoverEncounterDraftAfterFlushFailure(current);
      final currentAfter = state.value ?? current;
      final message = result.error is RpcFailure
          ? visitMessageForRpc(result.error! as RpcFailure)
          : result.error?.toString() ?? 'Unable to save encounter changes.';
      state = AsyncData(
        currentAfter.copyWith(
          saveStatus: DocumentationSaveStatus.error,
          errorMessage: '$message Saved changes were kept; remaining changes can be retried safely.',
        ),
      );
      return false;
    }

    final refreshed = await repo.getVisit(visitId: current.persistedVisit.id);
    ref.read(visitPatientSafetyProvider(_visitId).notifier).refreshBaseContext(current.persistedVisit.patientId);
    final afterNote = state.value ?? current;
    state = AsyncData(
      VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
        complaint: afterNote.complaint,
        history: afterNote.history,
        examination: afterNote.examination,
        diagnosis: afterNote.diagnosis,
        plan: afterNote.plan,
        richTextDrafts: afterNote.richTextDrafts,
        expectedUpdatedAt: afterNote.expectedUpdatedAt,
        noteEditMode: afterNote.noteEditMode,
        workspaceEditMode: afterNote.workspaceEditMode,
        saveStatus: afterNote.saveStatus,
        encounterDraft: result.remainingDraft,
      ),
    );
    _applyComposedDraft(result.remainingDraft);
    return true;
  }

  Future<void> _recoverEncounterDraftAfterFlushFailure(VisitDocumentationState current) async {
    try {
      final repo = ref.read(visitRepositoryProvider);
      final refreshed = await repo.getVisit(visitId: current.persistedVisit.id);
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
          encounterDraft: afterNote.encounterDraft,
          saveStatus: DocumentationSaveStatus.error,
        ),
      );
      _applyComposedDraft(afterNote.encounterDraft);
    } catch (_) {
      // Keep the pre-recovery state when refresh fails.
    }
  }

  String? _nullableSection(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // Delegation to sub-notifiers (keeps [VisitEncounterPersistence] stable).

  void stageCreateVitalSign({
    required String name,
    required String value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageCreateVitalSign(
          name: name,
          value: value,
          unit: unit,
          predefinedVitalSignId: predefinedVitalSignId,
        );
  }

  void stageUpdateVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageUpdateVitalSign(
          vitalSignId: vitalSignId,
          name: name,
          value: value,
          unit: unit,
          predefinedVitalSignId: predefinedVitalSignId,
        );
  }

  void stageArchiveVitalSign(String vitalSignId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageArchiveVitalSign(vitalSignId);
  }

  void stageCreateInvestigation({required String name, String? note, String? investigationId}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageCreateInvestigation(
          name: name,
          note: note,
          investigationId: investigationId,
        );
  }

  void stageUpdateInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
    bool updateInvestigationId = false,
  }) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageUpdateInvestigation(
          investigationLineId: investigationLineId,
          name: name,
          note: note,
          investigationId: investigationId,
          updateInvestigationId: updateInvestigationId,
        );
  }

  void stageArchiveInvestigation(String investigationLineId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageArchiveInvestigation(investigationLineId);
  }

  void stageInvestigationResult({required String investigationLineId, required String result}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageInvestigationResult(
          investigationLineId: investigationLineId,
          result: result,
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
    if (current == null || !_canMutateVisit(current)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageCreateTreatmentPlan(
          visitId: current.persistedVisit.id,
          patientId: current.persistedVisit.patientId,
          medicationName: medicationName,
          medicationId: medicationId,
          dosage: dosage,
          frequency: frequency,
          duration: duration,
          notes: notes,
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
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageUpdateTreatmentPlan(
          treatmentPlanId: treatmentPlanId,
          medicationName: medicationName,
          medicationId: medicationId,
          dosage: dosage,
          frequency: frequency,
          duration: duration,
          notes: notes,
        );
  }

  void stageArchiveTreatmentPlan(String treatmentPlanId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitClinicalDataProvider(_visitId).notifier).stageArchiveTreatmentPlan(treatmentPlanId);
  }

  void stageAttachment({
    required VisitAttachmentPick pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  }) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitAttachmentsProvider(_visitId).notifier).stageAttachment(
          pick: pick,
          label: label,
          uploadedBy: uploadedBy,
          uploadedByName: uploadedByName,
        );
  }

  void stageDeleteAttachment(String attachmentId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitAttachmentsProvider(_visitId).notifier).stageDeleteAttachment(attachmentId);
  }

  void stageCreateAllergy({required String substance, String? reaction}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageCreateAllergy(substance: substance, reaction: reaction);
  }

  void stageUpdateAllergy({required String allergyId, String? substance, String? reaction}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageUpdateAllergy(
          allergyId: allergyId,
          substance: substance,
          reaction: reaction,
        );
  }

  void stageArchiveAllergy(String allergyId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageArchiveAllergy(allergyId);
  }

  void stageCreateMedication({required String name, String? medicationId, String? note}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageCreateMedication(
          name: name,
          medicationId: medicationId,
          note: note,
        );
  }

  void stageUpdateMedication({required String medicationRecordId, String? name, String? medicationId, String? note}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageUpdateMedication(
          medicationRecordId: medicationRecordId,
          name: name,
          medicationId: medicationId,
          note: note,
        );
  }

  void stageArchiveMedication(String medicationRecordId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageArchiveMedication(medicationRecordId);
  }

  void stageCreateCondition({required String name, String? note}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageCreateCondition(name: name, note: note);
  }

  void stageUpdateCondition({required String conditionId, String? name, String? note}) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageUpdateCondition(
          conditionId: conditionId,
          name: name,
          note: note,
        );
  }

  void stageArchiveCondition(String conditionId) {
    if (state.value == null || !_canMutateVisit(state.value!)) return;
    ref.read(visitPatientSafetyProvider(_visitId).notifier).stageArchiveCondition(conditionId);
  }
}
