import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';

/// Clinical note save lifecycle on the visit documentation screen.
enum DocumentationSaveStatus { idle, saving, saved, stale, error }

/// Whether the clinical note section is in editing or read-only-after-save mode.
enum DocumentationEditMode { editing, readOnly }

@immutable
class VisitDocumentationState {
  const VisitDocumentationState({
    required this.visit,
    required this.complaint,
    required this.history,
    required this.examination,
    required this.diagnosis,
    required this.plan,
    required this.expectedUpdatedAt,
    this.richTextDrafts = const {},
    this.predefinedVitalSigns = const [],
    this.saveStatus = DocumentationSaveStatus.idle,
    this.noteEditMode = DocumentationEditMode.editing,
    this.errorMessage,
  });

  final VisitDetail visit;
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
  final DocumentationSaveStatus saveStatus;
  final DocumentationEditMode noteEditMode;
  final String? errorMessage;

  /// Whether the clinical note draft has unsaved changes.
  bool get hasUnsavedDraft {
    if (saveStatus == DocumentationSaveStatus.saving) {
      return false;
    }
    if (saveStatus == DocumentationSaveStatus.stale) {
      return true;
    }
    return noteEditMode == DocumentationEditMode.editing || saveStatus == DocumentationSaveStatus.idle;
  }

  bool get hasUnsavedChanges => hasUnsavedDraft;

  /// @deprecated Use [hasUnsavedDraft] with page-level permission gating.
  bool get needsSaveBeforeLeaving => hasUnsavedChanges;

  VisitDocumentationState copyWith({
    VisitDetail? visit,
    String? complaint,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
    DateTime? expectedUpdatedAt,
    Map<ClinicalNoteSection, List<dynamic>>? richTextDrafts,
    List<CatalogItem>? predefinedVitalSigns,
    DocumentationSaveStatus? saveStatus,
    DocumentationEditMode? noteEditMode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VisitDocumentationState(
      visit: visit ?? this.visit,
      complaint: complaint ?? this.complaint,
      history: history ?? this.history,
      examination: examination ?? this.examination,
      diagnosis: diagnosis ?? this.diagnosis,
      plan: plan ?? this.plan,
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      richTextDrafts: richTextDrafts ?? this.richTextDrafts,
      predefinedVitalSigns: predefinedVitalSigns ?? this.predefinedVitalSigns,
      saveStatus: saveStatus ?? this.saveStatus,
      noteEditMode: noteEditMode ?? this.noteEditMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static VisitDocumentationState fromVisit(VisitDetail visit, {List<CatalogItem> predefinedVitalSigns = const []}) {
    final note = visit.documentation;
    return VisitDocumentationState(
      visit: visit,
      complaint: note?.complaint ?? '',
      history: note?.history ?? '',
      examination: note?.examination ?? '',
      diagnosis: note?.diagnosis ?? '',
      plan: note?.plan ?? '',
      expectedUpdatedAt: note?.updatedAt ?? visit.updatedAt ?? DateTime.now().toUtc(),
      predefinedVitalSigns: predefinedVitalSigns,
    );
  }
}

final visitDocumentationProvider = AsyncNotifierProvider.autoDispose
    .family<VisitDocumentationNotifier, VisitDocumentationState, String>(VisitDocumentationNotifier.new);

/// Family arg is injected by [visitDocumentationProvider] via `NotifierT Function(String)`.
class VisitDocumentationNotifier extends AsyncNotifier<VisitDocumentationState> {
  VisitDocumentationNotifier(this._visitId);

  final String _visitId;

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

  /// Whether the visit can be submitted (in-progress only, with edit permission).
  bool canSubmitVisit(VisitDetail visit) => _canEditVisit(visit) && visit.status == VisitStatus.inProgress;

  /// Completes an in-progress visit. Persists local draft fields and keeps documentation editable afterward.
  Future<CompleteVisitResult> completeVisit() async {
    final current = state.value;
    if (current == null) {
      throw StateError('Visit documentation is not loaded.');
    }
    if (!canSubmitVisit(current.visit)) {
      throw RpcFailure(
        RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Only in-progress visits with edit permission can be submitted.',
        ),
      );
    }

    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .completeVisit(visitId: current.visit.id, expectedUpdatedAt: current.expectedUpdatedAt);

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
      state = AsyncData(
        VisitDocumentationState.fromVisit(refreshed, predefinedVitalSigns: current.predefinedVitalSigns).copyWith(
          complaint: current.complaint,
          history: current.history,
          examination: current.examination,
          diagnosis: current.diagnosis,
          plan: current.plan,
          expectedUpdatedAt: refreshed.documentation?.updatedAt ?? refreshed.updatedAt ?? current.expectedUpdatedAt,
          noteEditMode: DocumentationEditMode.editing,
          saveStatus: DocumentationSaveStatus.saved,
          clearError: true,
        ),
      );
      return result;
    } on RpcFailure catch (error) {
      if (error.code == 'DOCUMENTATION_REQUIRED_FOR_COMPLETE') {
        final currentAfter = state.value ?? current;
        state = AsyncData(
          currentAfter.copyWith(saveStatus: DocumentationSaveStatus.error, errorMessage: visitMessageForRpc(error)),
        );
      }
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
    if (current == null || !_canEditVisit(current.visit)) {
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

  /// Persists all local draft fields.
  ///
  /// Returns `false` when a save fails or the state is stale; `true` when
  /// everything is persisted (or there was nothing to save).
  Future<bool> saveAll() async {
    final current = state.value;
    if (current == null || !_canEditVisit(current.visit)) {
      return true;
    }

    if (current.hasUnsavedDraft) {
      await save();
      final afterNote = state.value;
      if (afterNote == null ||
          afterNote.saveStatus == DocumentationSaveStatus.error ||
          afterNote.saveStatus == DocumentationSaveStatus.stale) {
        return false;
      }
    }

    return true;
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (!_canEditVisit(current.visit)) {
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

  /// Refreshes visit metadata without discarding unsaved clinical note draft.
  Future<void> refreshVisitPreservingDraft() async {
    final current = state.value;
    if (current == null) {
      return;
    }

    final repo = ref.read(visitRepositoryProvider);
    final refreshed = await repo.getVisit(visitId: current.visit.id);
    final predefinedVitalSigns = await repo.listPredefinedVitalSigns();
    state = AsyncData(
      current.copyWith(
        visit: current.visit.copyWith(
          treatmentPlans: refreshed.treatmentPlans,
          vitalSigns: refreshed.vitalSigns,
          investigations: refreshed.investigations,
          status: refreshed.status,
          doctorName: refreshed.doctorName,
          visitDate: refreshed.visitDate,
          attachments: refreshed.attachments,
        ),
        predefinedVitalSigns: predefinedVitalSigns,
      ),
    );
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
