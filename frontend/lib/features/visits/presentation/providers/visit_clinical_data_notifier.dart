import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';

/// Clinical structured data staged for a visit encounter (vitals, investigations, prescriptions).
@immutable
class VisitClinicalDataState {
  const VisitClinicalDataState({
    this.persistedVisit,
    this.pendingVitalSigns = const [],
    this.vitalSignUpdates = const {},
    this.archivedVitalSignIds = const {},
    this.pendingInvestigations = const [],
    this.investigationUpdates = const {},
    this.archivedInvestigationIds = const {},
    this.pendingTreatmentPlans = const [],
    this.treatmentPlanUpdates = const {},
    this.archivedTreatmentPlanIds = const {},
    this.investigationResults = const {},
  });

  final VisitDetail? persistedVisit;
  final List<VisitVitalSign> pendingVitalSigns;
  final Map<String, VisitVitalSign> vitalSignUpdates;
  final Set<String> archivedVitalSignIds;
  final List<VisitInvestigation> pendingInvestigations;
  final Map<String, VisitInvestigation> investigationUpdates;
  final Set<String> archivedInvestigationIds;
  final List<TreatmentPlanItem> pendingTreatmentPlans;
  final Map<String, TreatmentPlanItem> treatmentPlanUpdates;
  final Set<String> archivedTreatmentPlanIds;
  final Map<String, String> investigationResults;

  bool get hasPendingDraft =>
      pendingVitalSigns.isNotEmpty ||
      vitalSignUpdates.isNotEmpty ||
      archivedVitalSignIds.isNotEmpty ||
      pendingInvestigations.isNotEmpty ||
      investigationUpdates.isNotEmpty ||
      archivedInvestigationIds.isNotEmpty ||
      pendingTreatmentPlans.isNotEmpty ||
      treatmentPlanUpdates.isNotEmpty ||
      archivedTreatmentPlanIds.isNotEmpty ||
      investigationResults.isNotEmpty;

  VisitEncounterDraft toEncounterDraftSlice() {
    return VisitEncounterDraft(
      pendingVitalSigns: pendingVitalSigns,
      vitalSignUpdates: vitalSignUpdates,
      archivedVitalSignIds: archivedVitalSignIds,
      pendingInvestigations: pendingInvestigations,
      investigationUpdates: investigationUpdates,
      archivedInvestigationIds: archivedInvestigationIds,
      pendingTreatmentPlans: pendingTreatmentPlans,
      treatmentPlanUpdates: treatmentPlanUpdates,
      archivedTreatmentPlanIds: archivedTreatmentPlanIds,
      investigationResults: investigationResults,
    );
  }

  VisitDetail applyTo(VisitDetail visit) => toEncounterDraftSlice().applyTo(visit);

  VisitClinicalDataState copyWith({
    VisitDetail? persistedVisit,
    List<VisitVitalSign>? pendingVitalSigns,
    Map<String, VisitVitalSign>? vitalSignUpdates,
    Set<String>? archivedVitalSignIds,
    List<VisitInvestigation>? pendingInvestigations,
    Map<String, VisitInvestigation>? investigationUpdates,
    Set<String>? archivedInvestigationIds,
    List<TreatmentPlanItem>? pendingTreatmentPlans,
    Map<String, TreatmentPlanItem>? treatmentPlanUpdates,
    Set<String>? archivedTreatmentPlanIds,
    Map<String, String>? investigationResults,
  }) {
    return VisitClinicalDataState(
      persistedVisit: persistedVisit ?? this.persistedVisit,
      pendingVitalSigns: pendingVitalSigns ?? this.pendingVitalSigns,
      vitalSignUpdates: vitalSignUpdates ?? this.vitalSignUpdates,
      archivedVitalSignIds: archivedVitalSignIds ?? this.archivedVitalSignIds,
      pendingInvestigations: pendingInvestigations ?? this.pendingInvestigations,
      investigationUpdates: investigationUpdates ?? this.investigationUpdates,
      archivedInvestigationIds: archivedInvestigationIds ?? this.archivedInvestigationIds,
      pendingTreatmentPlans: pendingTreatmentPlans ?? this.pendingTreatmentPlans,
      treatmentPlanUpdates: treatmentPlanUpdates ?? this.treatmentPlanUpdates,
      archivedTreatmentPlanIds: archivedTreatmentPlanIds ?? this.archivedTreatmentPlanIds,
      investigationResults: investigationResults ?? this.investigationResults,
    );
  }

  static VisitClinicalDataState fromEncounterDraft(VisitEncounterDraft draft) {
    return VisitClinicalDataState(
      pendingVitalSigns: draft.pendingVitalSigns,
      vitalSignUpdates: draft.vitalSignUpdates,
      archivedVitalSignIds: draft.archivedVitalSignIds,
      pendingInvestigations: draft.pendingInvestigations,
      investigationUpdates: draft.investigationUpdates,
      archivedInvestigationIds: draft.archivedInvestigationIds,
      pendingTreatmentPlans: draft.pendingTreatmentPlans,
      treatmentPlanUpdates: draft.treatmentPlanUpdates,
      archivedTreatmentPlanIds: draft.archivedTreatmentPlanIds,
      investigationResults: draft.investigationResults,
    );
  }
}

final visitClinicalDataProvider = NotifierProvider.family<VisitClinicalDataNotifier, VisitClinicalDataState, String>(
  VisitClinicalDataNotifier.new,
);

class VisitClinicalDataNotifier extends Notifier<VisitClinicalDataState> {
  VisitClinicalDataNotifier(String _);


  @override
  VisitClinicalDataState build() => const VisitClinicalDataState();

  void setPersistedVisit(VisitDetail visit) {
    state = state.copyWith(persistedVisit: visit);
  }

  void replaceFromEncounterDraft(VisitEncounterDraft draft) {
    state = VisitClinicalDataState.fromEncounterDraft(draft);
  }

  void clearDraft() {
    state = const VisitClinicalDataState();
  }

  void _apply(VisitClinicalDataState next) {
    state = next;
  }

  VisitDetail _effectiveVisit() {
    final base = state.persistedVisit;
    if (base == null) {
      throw StateError('Persisted visit is not loaded for clinical data notifier.');
    }
    return state.applyTo(base);
  }

  VisitVitalSign? findVitalSign(String id) {
    for (final sign in _effectiveVisit().vitalSigns) {
      if (sign.id == id) return sign;
    }
    return null;
  }

  VisitInvestigation? findInvestigation(String id) {
    final effectiveVisit = _effectiveVisit();
    for (final item in effectiveVisit.investigations) {
      if (item.id == id) return item;
    }
    for (final item in effectiveVisit.pendingInvestigations) {
      if (item.id == id) return item;
    }
    return null;
  }

  TreatmentPlanItem? findTreatmentPlan(String id) {
    for (final plan in _effectiveVisit().treatmentPlans) {
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
    final sign = VisitVitalSign(
      id: newVisitDraftId(),
      name: name,
      value: value,
      unit: unit,
      predefinedVitalSignId: predefinedVitalSignId,
    );
    _apply(state.copyWith(pendingVitalSigns: [...state.pendingVitalSigns, sign]));
  }

  void stageUpdateVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    if (isVisitDraftId(vitalSignId)) {
      final updated = state.pendingVitalSigns
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
      _apply(state.copyWith(pendingVitalSigns: updated));
      return;
    }
    final existing = findVitalSign(vitalSignId);
    if (existing == null) return;
    final updated = VisitVitalSign(
      id: existing.id,
      name: name ?? existing.name,
      value: value ?? existing.value,
      unit: unit ?? existing.unit,
      predefinedVitalSignId: predefinedVitalSignId ?? existing.predefinedVitalSignId,
    );
    _apply(state.copyWith(vitalSignUpdates: {...state.vitalSignUpdates, vitalSignId: updated}));
  }

  void stageArchiveVitalSign(String vitalSignId) {
    if (isVisitDraftId(vitalSignId)) {
      _apply(state.copyWith(pendingVitalSigns: state.pendingVitalSigns.where((sign) => sign.id != vitalSignId).toList()));
      return;
    }
    _apply(
      state.copyWith(
        archivedVitalSignIds: {...state.archivedVitalSignIds, vitalSignId},
        vitalSignUpdates: Map<String, VisitVitalSign>.from(state.vitalSignUpdates)..remove(vitalSignId),
      ),
    );
  }

  void stageCreateInvestigation({required String name, String? note, String? investigationId}) {
    final investigation = VisitInvestigation(
      id: newVisitDraftId(),
      name: name,
      note: note,
      investigationId: investigationId,
    );
    _apply(state.copyWith(pendingInvestigations: [...state.pendingInvestigations, investigation]));
  }

  void stageUpdateInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
    bool updateInvestigationId = false,
  }) {
    if (isVisitDraftId(investigationLineId)) {
      final updated = state.pendingInvestigations
          .map(
            (item) => item.id == investigationLineId
                ? VisitInvestigation(
                    id: item.id,
                    name: name ?? item.name,
                    note: note ?? item.note,
                    investigationId: updateInvestigationId ? investigationId : item.investigationId,
                  )
                : item,
          )
          .toList(growable: false);
      _apply(state.copyWith(pendingInvestigations: updated));
      return;
    }
    final existing = findInvestigation(investigationLineId);
    if (existing == null) return;
    final updated = VisitInvestigation(
      id: existing.id,
      name: name ?? existing.name,
      note: note ?? existing.note,
      investigationId: updateInvestigationId ? investigationId : existing.investigationId,
      result: existing.result,
      resultRecordedAt: existing.resultRecordedAt,
      orderedVisitId: existing.orderedVisitId,
      orderedVisitDate: existing.orderedVisitDate,
    );
    _apply(state.copyWith(investigationUpdates: {...state.investigationUpdates, investigationLineId: updated}));
  }

  void stageArchiveInvestigation(String investigationLineId) {
    final clearedResults = Map<String, String>.from(state.investigationResults)..remove(investigationLineId);
    if (isVisitDraftId(investigationLineId)) {
      _apply(
        state.copyWith(
          pendingInvestigations: state.pendingInvestigations.where((item) => item.id != investigationLineId).toList(),
          investigationResults: clearedResults,
        ),
      );
      return;
    }
    _apply(
      state.copyWith(
        archivedInvestigationIds: {...state.archivedInvestigationIds, investigationLineId},
        investigationUpdates: Map<String, VisitInvestigation>.from(state.investigationUpdates)..remove(investigationLineId),
        investigationResults: clearedResults,
      ),
    );
  }

  void stageInvestigationResult({required String investigationLineId, required String result}) {
    _apply(
      state.copyWith(
        investigationResults: {...state.investigationResults, investigationLineId: result.trim()},
      ),
    );
  }

  void stageCreateTreatmentPlan({
    required String visitId,
    required String patientId,
    required String medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) {
    final plan = TreatmentPlanItem(
      id: newVisitDraftId(),
      visitId: visitId,
      patientId: patientId,
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
    _apply(state.copyWith(pendingTreatmentPlans: [...state.pendingTreatmentPlans, plan]));
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
    if (isVisitDraftId(treatmentPlanId)) {
      final updated = state.pendingTreatmentPlans
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
      _apply(state.copyWith(pendingTreatmentPlans: updated));
      return;
    }
    final existing = findTreatmentPlan(treatmentPlanId);
    if (existing == null) return;
    final updated = existing.copyWith(
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
    _apply(state.copyWith(treatmentPlanUpdates: {...state.treatmentPlanUpdates, treatmentPlanId: updated}));
  }

  void stageArchiveTreatmentPlan(String treatmentPlanId) {
    if (isVisitDraftId(treatmentPlanId)) {
      _apply(
        state.copyWith(
          pendingTreatmentPlans: state.pendingTreatmentPlans.where((plan) => plan.id != treatmentPlanId).toList(),
        ),
      );
      return;
    }
    _apply(
      state.copyWith(
        archivedTreatmentPlanIds: {...state.archivedTreatmentPlanIds, treatmentPlanId},
        treatmentPlanUpdates: Map<String, TreatmentPlanItem>.from(state.treatmentPlanUpdates)..remove(treatmentPlanId),
      ),
    );
  }
}
