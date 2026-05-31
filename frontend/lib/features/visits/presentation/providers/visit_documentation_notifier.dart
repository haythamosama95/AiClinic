import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// SOAP save lifecycle on the visit documentation screen.
enum SoapSaveStatus {
  idle,
  saving,
  saved,
  stale,
  error,
}

@immutable
class VisitDocumentationState {
  const VisitDocumentationState({
    required this.visit,
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
    required this.expectedUpdatedAt,
    this.saveStatus = SoapSaveStatus.idle,
    this.errorMessage,
    required this.canEdit,
  });

  final VisitDetail visit;
  final String subjective;
  final String objective;
  final String assessment;
  final String plan;
  final DateTime expectedUpdatedAt;
  final SoapSaveStatus saveStatus;
  final String? errorMessage;
  final bool canEdit;

  bool get isEditable => canEdit && visit.status == VisitStatus.inProgress;

  VisitDocumentationState copyWith({
    VisitDetail? visit,
    String? subjective,
    String? objective,
    String? assessment,
    String? plan,
    DateTime? expectedUpdatedAt,
    SoapSaveStatus? saveStatus,
    String? errorMessage,
    bool? canEdit,
    bool clearError = false,
  }) {
    return VisitDocumentationState(
      visit: visit ?? this.visit,
      subjective: subjective ?? this.subjective,
      objective: objective ?? this.objective,
      assessment: assessment ?? this.assessment,
      plan: plan ?? this.plan,
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      saveStatus: saveStatus ?? this.saveStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      canEdit: canEdit ?? this.canEdit,
    );
  }

  static VisitDocumentationState fromVisit(VisitDetail visit, {required bool canEdit}) {
    final soap = visit.soap;
    return VisitDocumentationState(
      visit: visit,
      subjective: soap?.subjective ?? '',
      objective: soap?.objective ?? '',
      assessment: soap?.assessment ?? '',
      plan: soap?.plan ?? '',
      expectedUpdatedAt: soap?.updatedAt ?? DateTime.now().toUtc(),
      canEdit: canEdit,
    );
  }
}

final visitDocumentationProvider =
    AsyncNotifierProvider.autoDispose.family<VisitDocumentationNotifier, VisitDocumentationState, String>(
  VisitDocumentationNotifier.new,
);

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

    final permissions = ref.read(permissionServiceProvider);
    final visit = await ref.read(visitRepositoryProvider).getVisit(visitId: visitId);
    return VisitDocumentationState.fromVisit(visit, canEdit: permissions.canEditVisitSoap());
  }

  void updateSubjective(String value) => _updateDraft(subjective: value);

  void updateObjective(String value) => _updateDraft(objective: value);

  void updateAssessment(String value) => _updateDraft(assessment: value);

  void updatePlan(String value) => _updateDraft(plan: value);

  void _updateDraft({String? subjective, String? objective, String? assessment, String? plan}) {
    final current = state.value;
    if (current == null || !current.isEditable) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        subjective: subjective,
        objective: objective,
        assessment: assessment,
        plan: plan,
        saveStatus: SoapSaveStatus.idle,
        clearError: true,
      ),
    );
  }

  Future<void> save() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    if (!current.isEditable) {
      return;
    }

    state = AsyncData(current.copyWith(saveStatus: SoapSaveStatus.saving, clearError: true));

    try {
      final saved = await ref.read(visitRepositoryProvider).saveSoapNote(
        visitId: current.visit.id,
        expectedUpdatedAt: current.expectedUpdatedAt,
        subjective: _nullableSection(current.subjective),
        objective: _nullableSection(current.objective),
        assessment: _nullableSection(current.assessment),
        plan: _nullableSection(current.plan),
        specialtyFormJson: current.visit.soap?.specialtyFormJson,
      );

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
      final next = VisitDocumentationState.fromVisit(refreshed, canEdit: current.canEdit).copyWith(
        subjective: current.subjective,
        objective: current.objective,
        assessment: current.assessment,
        plan: current.plan,
        expectedUpdatedAt: saved.updatedAt,
        saveStatus: SoapSaveStatus.saved,
      );
      state = AsyncData(next);
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'STALE_SOAP') {
        state = AsyncData(
          currentAfter.copyWith(
            saveStatus: SoapSaveStatus.stale,
            errorMessage: visitMessageForRpc(error),
          ),
        );
        return;
      }
      state = AsyncData(
        currentAfter.copyWith(
          saveStatus: SoapSaveStatus.error,
          errorMessage: visitMessageForRpc(error),
        ),
      );
    } catch (error) {
      final currentAfter = state.value ?? current;
      state = AsyncData(
        currentAfter.copyWith(
          saveStatus: SoapSaveStatus.error,
          errorMessage: error.toString(),
        ),
      );
    }
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
