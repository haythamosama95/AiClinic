import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
/// Patient safety context plus in-visit staged mutations.
@immutable
class VisitPatientSafetyState {
  const VisitPatientSafetyState({
    this.baseContext,
    this.safetyDraft = const PatientSafetyDraft(),
  });

  final PatientSafetyContext? baseContext;
  final PatientSafetyDraft safetyDraft;

  bool get hasPendingDraft => !safetyDraft.isEmpty;

  PatientSafetyContext get effectiveContext {
    final base = baseContext ?? const PatientSafetyContext();
    return safetyDraft.applyTo(base);
  }

  VisitEncounterDraft toEncounterDraftSlice() {
    return VisitEncounterDraft(patientSafety: safetyDraft);
  }

  VisitPatientSafetyState copyWith({
    PatientSafetyContext? baseContext,
    PatientSafetyDraft? safetyDraft,
  }) {
    return VisitPatientSafetyState(
      baseContext: baseContext ?? this.baseContext,
      safetyDraft: safetyDraft ?? this.safetyDraft,
    );
  }

  static VisitPatientSafetyState fromEncounterDraft(
    PatientSafetyContext? base,
    VisitEncounterDraft draft,
  ) {
    return VisitPatientSafetyState(baseContext: base, safetyDraft: draft.patientSafety);
  }
}

/// Loads patient safety context and stages visit-scoped safety mutations.
final visitPatientSafetyProvider = AsyncNotifierProvider.family<VisitPatientSafetyNotifier, VisitPatientSafetyState, String>(
  VisitPatientSafetyNotifier.new,
);

class VisitPatientSafetyNotifier extends AsyncNotifier<VisitPatientSafetyState> {
  VisitPatientSafetyNotifier(this._visitId);

  final String _visitId;

  @override
  Future<VisitPatientSafetyState> build() async => const VisitPatientSafetyState();

  Future<void> ensureLoaded(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) {
      state = const AsyncData(VisitPatientSafetyState());
      return;
    }
    if (state.value?.baseContext != null) {
      return;
    }
    final base = await ref.read(visitRepositoryProvider).getPatientSafetyContext(patientId: trimmed);
    final currentDraft = state.value?.safetyDraft ?? const PatientSafetyDraft();
    state = AsyncData(VisitPatientSafetyState(baseContext: base, safetyDraft: currentDraft));
  }

  void replaceSafetyDraft(PatientSafetyDraft draft) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(safetyDraft: draft));
  }

  void clearDraft() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(safetyDraft: const PatientSafetyDraft()));
  }

  void _applySafetyDraft(PatientSafetyDraft next) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(safetyDraft: next));
  }

  PatientAllergy? findAllergy(String id) {
    final current = state.value;
    if (current == null) return null;
    final safety = current.safetyDraft;
    final staged = safety.allergyUpdates[id];
    if (staged != null) return staged;
    for (final allergy in safety.pendingAllergies) {
      if (allergy.id == id) return allergy;
    }
    final base = current.baseContext;
    if (base != null) {
      for (final allergy in base.allergies) {
        if (allergy.id == id) return allergy;
      }
    }
    return null;
  }

  PatientMedication? findMedication(String id) {
    final current = state.value;
    if (current == null) return null;
    final safety = current.safetyDraft;
    final staged = safety.medicationUpdates[id];
    if (staged != null) return staged;
    for (final med in safety.pendingMedications) {
      if (med.id == id) return med;
    }
    final base = current.baseContext;
    if (base != null) {
      for (final med in base.currentMedications) {
        if (med.id == id) return med;
      }
    }
    return null;
  }

  PatientChronicCondition? findCondition(String id) {
    final current = state.value;
    if (current == null) return null;
    final safety = current.safetyDraft;
    final staged = safety.conditionUpdates[id];
    if (staged != null) return staged;
    for (final condition in safety.pendingConditions) {
      if (condition.id == id) return condition;
    }
    final base = current.baseContext;
    if (base != null) {
      for (final condition in base.chronicConditions) {
        if (condition.id == id) return condition;
      }
    }
    return null;
  }

  void stageCreateAllergy({required String substance, String? reaction}) {
    final allergy = PatientAllergy(id: newVisitDraftId(), substance: substance, reaction: reaction);
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    _applySafetyDraft(safety.copyWith(pendingAllergies: [...safety.pendingAllergies, allergy]));
  }

  void stageUpdateAllergy({required String allergyId, String? substance, String? reaction}) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
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
      _applySafetyDraft(safety.copyWith(pendingAllergies: updated));
      return;
    }
    final existing = findAllergy(allergyId);
    if (existing == null && substance == null) return;
    final updated = PatientAllergy(
      id: allergyId,
      substance: substance ?? existing?.substance ?? '',
      reaction: reaction ?? existing?.reaction,
    );
    _applySafetyDraft(safety.copyWith(allergyUpdates: {...safety.allergyUpdates, allergyId: updated}));
  }

  void stageArchiveAllergy(String allergyId) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    if (isVisitDraftId(allergyId)) {
      _applySafetyDraft(
        safety.copyWith(
          pendingAllergies: safety.pendingAllergies.where((allergy) => allergy.id != allergyId).toList(),
        ),
      );
      return;
    }
    _applySafetyDraft(
      safety.copyWith(
        archivedAllergyIds: {...safety.archivedAllergyIds, allergyId},
        allergyUpdates: Map<String, PatientAllergy>.from(safety.allergyUpdates)..remove(allergyId),
      ),
    );
  }

  void stageCreateMedication({required String name, String? medicationId, String? note}) {
    final med = PatientMedication(id: newVisitDraftId(), name: name, medicationId: medicationId, note: note);
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    _applySafetyDraft(safety.copyWith(pendingMedications: [...safety.pendingMedications, med]));
  }

  void stageUpdateMedication({required String medicationRecordId, String? name, String? medicationId, String? note}) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
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
      _applySafetyDraft(safety.copyWith(pendingMedications: updated));
      return;
    }
    final existing = findMedication(medicationRecordId);
    if (existing == null && name == null) return;
    final updated = PatientMedication(
      id: medicationRecordId,
      name: name ?? existing?.name ?? '',
      medicationId: medicationId ?? existing?.medicationId,
      note: note ?? existing?.note,
    );
    _applySafetyDraft(
      safety.copyWith(medicationUpdates: {...safety.medicationUpdates, medicationRecordId: updated}),
    );
  }

  void stageArchiveMedication(String medicationRecordId) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    if (isVisitDraftId(medicationRecordId)) {
      _applySafetyDraft(
        safety.copyWith(
          pendingMedications: safety.pendingMedications.where((med) => med.id != medicationRecordId).toList(),
        ),
      );
      return;
    }
    _applySafetyDraft(
      safety.copyWith(
        archivedMedicationIds: {...safety.archivedMedicationIds, medicationRecordId},
        medicationUpdates: Map<String, PatientMedication>.from(safety.medicationUpdates)..remove(medicationRecordId),
      ),
    );
  }

  void stageCreateCondition({required String name, String? note}) {
    final condition = PatientChronicCondition(id: newVisitDraftId(), name: name, note: note);
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    _applySafetyDraft(safety.copyWith(pendingConditions: [...safety.pendingConditions, condition]));
  }

  void stageUpdateCondition({required String conditionId, String? name, String? note}) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    if (isVisitDraftId(conditionId)) {
      final updated = safety.pendingConditions
          .map(
            (condition) => condition.id == conditionId
                ? PatientChronicCondition(id: condition.id, name: name ?? condition.name, note: note ?? condition.note)
                : condition,
          )
          .toList(growable: false);
      _applySafetyDraft(safety.copyWith(pendingConditions: updated));
      return;
    }
    final existing = findCondition(conditionId);
    if (existing == null && name == null) return;
    final updated = PatientChronicCondition(
      id: conditionId,
      name: name ?? existing?.name ?? '',
      note: note ?? existing?.note,
    );
    _applySafetyDraft(safety.copyWith(conditionUpdates: {...safety.conditionUpdates, conditionId: updated}));
  }

  void stageArchiveCondition(String conditionId) {
    final safety = state.value?.safetyDraft ?? const PatientSafetyDraft();
    if (isVisitDraftId(conditionId)) {
      _applySafetyDraft(
        safety.copyWith(
          pendingConditions: safety.pendingConditions.where((condition) => condition.id != conditionId).toList(),
        ),
      );
      return;
    }
    _applySafetyDraft(
      safety.copyWith(
        archivedConditionIds: {...safety.archivedConditionIds, conditionId},
        conditionUpdates: Map<String, PatientChronicCondition>.from(safety.conditionUpdates)..remove(conditionId),
      ),
    );
  }

  Future<void> refreshBaseContext(String patientId) async {
    if (patientId.trim().isEmpty) return;
    final base = await ref.read(visitRepositoryProvider).getPatientSafetyContext(patientId: patientId);
    final current = state.value ?? const VisitPatientSafetyState();
    state = AsyncData(current.copyWith(baseContext: base));
  }
}

/// Legacy patient-id keyed provider for screens outside the visit workspace.
final patientSafetyProvider = AsyncNotifierProvider.autoDispose
    .family<LegacyPatientSafetyNotifier, PatientSafetyContext, String>(LegacyPatientSafetyNotifier.new);

class LegacyPatientSafetyNotifier extends AsyncNotifier<PatientSafetyContext> {
  LegacyPatientSafetyNotifier(this._patientId);

  final String _patientId;

  @override
  Future<PatientSafetyContext> build() async {
    final patientId = _patientId.trim();
    if (patientId.isEmpty) {
      throw StateError('Patient id is required.');
    }
    return ref.read(visitRepositoryProvider).getPatientSafetyContext(patientId: patientId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await build());
  }
}
