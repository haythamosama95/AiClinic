import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// SOAP save lifecycle on the visit documentation screen.
enum SoapSaveStatus { idle, saving, saved, stale, error }

@immutable
class VisitDocumentationState {
  const VisitDocumentationState({
    required this.visit,
    required this.subjective,
    required this.objective,
    required this.assessment,
    required this.plan,
    required this.specialtyFormJson,
    required this.specialtySchema,
    this.specialtyFieldErrors = const {},
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
  final Map<String, dynamic> specialtyFormJson;
  final SpecialtyFormSchema specialtySchema;
  final Map<String, String> specialtyFieldErrors;
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
    Map<String, dynamic>? specialtyFormJson,
    SpecialtyFormSchema? specialtySchema,
    Map<String, String>? specialtyFieldErrors,
    DateTime? expectedUpdatedAt,
    SoapSaveStatus? saveStatus,
    String? errorMessage,
    bool? canEdit,
    bool clearError = false,
    bool clearSpecialtyErrors = false,
  }) {
    return VisitDocumentationState(
      visit: visit ?? this.visit,
      subjective: subjective ?? this.subjective,
      objective: objective ?? this.objective,
      assessment: assessment ?? this.assessment,
      plan: plan ?? this.plan,
      specialtyFormJson: specialtyFormJson ?? this.specialtyFormJson,
      specialtySchema: specialtySchema ?? this.specialtySchema,
      specialtyFieldErrors: clearSpecialtyErrors ? const {} : (specialtyFieldErrors ?? this.specialtyFieldErrors),
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      saveStatus: saveStatus ?? this.saveStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      canEdit: canEdit ?? this.canEdit,
    );
  }

  static VisitDocumentationState fromVisit(
    VisitDetail visit, {
    required bool canEdit,
    SpecialtyFormSchema specialtySchema = const SpecialtyFormSchema(),
  }) {
    final soap = visit.soap;
    return VisitDocumentationState(
      visit: visit,
      subjective: soap?.subjective ?? '',
      objective: soap?.objective ?? '',
      assessment: soap?.assessment ?? '',
      plan: soap?.plan ?? '',
      specialtyFormJson: Map<String, dynamic>.from(soap?.specialtyFormJson ?? const {}),
      specialtySchema: specialtySchema,
      expectedUpdatedAt: soap?.updatedAt ?? DateTime.now().toUtc(),
      canEdit: canEdit,
    );
  }
}

final visitDocumentationProvider = AsyncNotifierProvider.autoDispose
    .family<VisitDocumentationNotifier, VisitDocumentationState, String>(VisitDocumentationNotifier.new);

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
    final permissions = ref.read(permissionServiceProvider);
    final visit = await repo.getVisit(visitId: visitId);
    final schemaJson = await repo.getSpecialtyFormSchema();
    final specialtySchema = SpecialtyFormSchema.parse(schemaJson);
    return VisitDocumentationState.fromVisit(
      visit,
      canEdit: permissions.canEditVisitSoap(),
      specialtySchema: specialtySchema,
    );
  }

  void updateSubjective(String value) => _updateDraft(subjective: value);

  void updateObjective(String value) => _updateDraft(objective: value);

  void updateAssessment(String value) => _updateDraft(assessment: value);

  void updatePlan(String value) => _updateDraft(plan: value);

  void updateSpecialtyField(String key, Object? value) {
    final current = state.value;
    if (current == null || !current.isEditable) {
      return;
    }
    final nextJson = Map<String, dynamic>.from(current.specialtyFormJson);
    if (value == null) {
      nextJson.remove(key);
    } else {
      nextJson[key] = value;
    }
    state = AsyncData(
      current.copyWith(
        specialtyFormJson: nextJson,
        saveStatus: SoapSaveStatus.idle,
        clearError: true,
        clearSpecialtyErrors: true,
      ),
    );
  }

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

    final specialtyErrors = current.specialtySchema.hasFields
        ? SpecialtyFormSchema.validateValues(current.specialtyFormJson, current.specialtySchema)
        : const <String, String>{};
    final specialtyPayload = current.specialtySchema.encodeForSave(current.specialtyFormJson);
    if (specialtyErrors.isNotEmpty) {
      state = AsyncData(
        current.copyWith(
          specialtyFieldErrors: specialtyErrors,
          saveStatus: SoapSaveStatus.error,
          errorMessage: 'Fix specialty field errors before saving.',
        ),
      );
      return;
    }

    state = AsyncData(
      current.copyWith(saveStatus: SoapSaveStatus.saving, clearError: true, clearSpecialtyErrors: true),
    );

    try {
      final saved = await ref
          .read(visitRepositoryProvider)
          .saveSoapNote(
            visitId: current.visit.id,
            expectedUpdatedAt: current.expectedUpdatedAt,
            subjective: _nullableSection(current.subjective),
            objective: _nullableSection(current.objective),
            assessment: _nullableSection(current.assessment),
            plan: _nullableSection(current.plan),
            specialtyFormJson: specialtyPayload.isEmpty ? null : specialtyPayload,
          );

      final refreshed = await ref.read(visitRepositoryProvider).getVisit(visitId: current.visit.id);
      final next =
          VisitDocumentationState.fromVisit(
            refreshed,
            canEdit: current.canEdit,
            specialtySchema: current.specialtySchema,
          ).copyWith(
            subjective: current.subjective,
            objective: current.objective,
            assessment: current.assessment,
            plan: current.plan,
            specialtyFormJson: specialtyPayload.isEmpty ? current.specialtyFormJson : specialtyPayload,
            expectedUpdatedAt: saved.updatedAt,
            saveStatus: SoapSaveStatus.saved,
          );
      state = AsyncData(next);
    } on RpcFailure catch (error) {
      final currentAfter = state.value ?? current;
      if (error.code == 'STALE_SOAP') {
        state = AsyncData(
          currentAfter.copyWith(saveStatus: SoapSaveStatus.stale, errorMessage: visitMessageForRpc(error)),
        );
        return;
      }
      state = AsyncData(
        currentAfter.copyWith(saveStatus: SoapSaveStatus.error, errorMessage: visitMessageForRpc(error)),
      );
    } catch (error) {
      final currentAfter = state.value ?? current;
      state = AsyncData(currentAfter.copyWith(saveStatus: SoapSaveStatus.error, errorMessage: error.toString()));
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
