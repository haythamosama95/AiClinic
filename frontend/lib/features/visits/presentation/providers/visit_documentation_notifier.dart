import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
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

  /// @deprecated Use [hasUnsavedDraft] with page-level permission gating.
  bool get needsSaveBeforeLeaving => hasUnsavedDraft;

  VisitDocumentationState copyWith({
    VisitDetail? visit,
    String? complaint,
    String? history,
    String? examination,
    String? diagnosis,
    String? plan,
    DateTime? expectedUpdatedAt,
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
      saveStatus: saveStatus ?? this.saveStatus,
      noteEditMode: noteEditMode ?? this.noteEditMode,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static VisitDocumentationState fromVisit(VisitDetail visit) {
    final note = visit.documentation;
    return VisitDocumentationState(
      visit: visit,
      complaint: note?.complaint ?? '',
      history: note?.history ?? '',
      examination: note?.examination ?? '',
      diagnosis: note?.diagnosis ?? '',
      plan: note?.plan ?? '',
      expectedUpdatedAt: note?.updatedAt ?? visit.updatedAt ?? DateTime.now().toUtc(),
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
    return VisitDocumentationState.fromVisit(visit);
  }

  bool _canEditVisit(VisitDetail visit) {
    final permissions = ref.read(permissionServiceProvider);
    final branchIds = ref.read(authSessionProvider).context?.branchIds ?? const <String>[];
    return permissions.canEditVisitSoap() && branchIds.contains(visit.branchId);
  }

  void updateComplaint(String value) => _updateDraft(complaint: value);

  void updateHistory(String value) => _updateDraft(history: value);

  void updateExamination(String value) => _updateDraft(examination: value);

  void updateDiagnosis(String value) => _updateDraft(diagnosis: value);

  void updatePlan(String value) => _updateDraft(plan: value);

  void _updateDraft({String? complaint, String? history, String? examination, String? diagnosis, String? plan}) {
    final current = state.value;
    if (current == null || !_canEditVisit(current.visit)) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        complaint: complaint,
        history: history,
        examination: examination,
        diagnosis: diagnosis,
        plan: plan,
        saveStatus: DocumentationSaveStatus.idle,
        clearError: true,
      ),
    );
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
      final next = VisitDocumentationState.fromVisit(refreshed).copyWith(
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

    final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
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
      ),
    );
  }

  Future<void> reloadVisit() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  Future<void> reloadAfterStale() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }

  String? _nullableSection(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
