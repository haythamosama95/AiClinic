import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';

/// Result of flushing an encounter draft to the server.
class VisitEncounterFlushResult {
  const VisitEncounterFlushResult({
    required this.success,
    required this.remainingDraft,
    this.error,
  });

  final bool success;
  final VisitEncounterDraft remainingDraft;
  final Object? error;
}

typedef EncounterDraftUpdater = void Function(VisitEncounterDraft draft);

/// Persists encounter draft items one RPC at a time, removing each from the draft on success.
class VisitEncounterFlusher {
  const VisitEncounterFlusher({
    required this.repository,
    required this.attachmentService,
  });

  final VisitRepository repository;
  final VisitAttachmentService attachmentService;

  /// Flushes [initialDraft] for [visit]. Calls [onDraftUpdated] after each successful item.
  Future<VisitEncounterFlushResult> flush({
    required VisitDetail visit,
    required VisitDetail persistedVisit,
    required String? organizationId,
    required VisitEncounterDraft initialDraft,
    required EncounterDraftUpdater onDraftUpdated,
  }) async {
    var draft = initialDraft;

    void publish(VisitEncounterDraft next) {
      draft = next;
      onDraftUpdated(draft);
    }

    try {
      for (final id in [...draft.archivedVitalSignIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archiveVisitVitalSign(vitalSignId: id);
          publish(draft.copyWith(archivedVitalSignIds: {...draft.archivedVitalSignIds}..remove(id)));
        }
      }

      for (final sign in [...draft.pendingVitalSigns]) {
        await repository.createVisitVitalSign(
          visitId: visit.id,
          name: sign.name,
          value: sign.value,
          unit: sign.unit,
          predefinedVitalSignId: sign.predefinedVitalSignId,
        );
        publish(draft.copyWith(pendingVitalSigns: draft.pendingVitalSigns.where((s) => s.id != sign.id).toList()));
      }

      for (final entry in Map<String, VisitVitalSign>.from(draft.vitalSignUpdates).entries) {
        final vitalSignId = entry.key;
        final updated = draft.vitalSignUpdates[vitalSignId]!;
        if (!isVisitDraftId(vitalSignId)) {
          await repository.updateVisitVitalSign(
            vitalSignId: vitalSignId,
            name: updated.name,
            value: updated.value,
            unit: updated.unit,
            predefinedVitalSignId: updated.predefinedVitalSignId,
          );
          final nextUpdates = Map.of(draft.vitalSignUpdates)..remove(vitalSignId);
          publish(draft.copyWith(vitalSignUpdates: nextUpdates));
        }
      }

      for (final id in [...draft.archivedInvestigationIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archiveVisitInvestigation(investigationLineId: id);
          publish(draft.copyWith(archivedInvestigationIds: {...draft.archivedInvestigationIds}..remove(id)));
        }
      }

      final investigationResultIdRemap = <String, String>{};
      for (final investigation in [...draft.pendingInvestigations]) {
        final persistedId = await repository.createVisitInvestigation(
          visitId: visit.id,
          name: investigation.name,
          note: investigation.note,
          investigationId: investigation.investigationId,
        );
        if (isVisitDraftId(investigation.id)) {
          investigationResultIdRemap[investigation.id] = persistedId;
        }
        var nextResults = draft.investigationResults;
        final stagedResult = nextResults.remove(investigation.id);
        if (stagedResult != null) {
          nextResults = {...nextResults, persistedId: stagedResult};
        }
        publish(
          draft.copyWith(
            pendingInvestigations: draft.pendingInvestigations.where((i) => i.id != investigation.id).toList(),
            investigationResults: nextResults,
          ),
        );
      }

      for (final entry in Map<String, VisitInvestigation>.from(draft.investigationUpdates).entries) {
        final investigationLineId = entry.key;
        final updated = draft.investigationUpdates[investigationLineId]!;
        if (!isVisitDraftId(investigationLineId)) {
          final existing = persistedVisit.investigations.where((i) => i.id == investigationLineId).firstOrNull;
          final investigationIdChanged = existing?.investigationId != updated.investigationId;
          await repository.updateVisitInvestigation(
            investigationLineId: investigationLineId,
            name: updated.name,
            note: updated.note,
            investigationId: updated.investigationId,
            updateInvestigationId: investigationIdChanged,
          );
          final nextUpdates = Map.of(draft.investigationUpdates)..remove(investigationLineId);
          publish(draft.copyWith(investigationUpdates: nextUpdates));
        }
      }

      for (final entry in Map<String, String>.from(draft.investigationResults).entries) {
        final investigationLineId = investigationResultIdRemap[entry.key] ?? entry.key;
        if (isVisitDraftId(investigationLineId)) {
          continue;
        }
        await repository.recordInvestigationResult(investigationLineId: investigationLineId, result: entry.value);
        final nextResults = Map.of(draft.investigationResults)..remove(entry.key);
        publish(draft.copyWith(investigationResults: nextResults));
      }

      for (final id in [...draft.archivedTreatmentPlanIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archiveTreatmentPlan(treatmentPlanId: id);
          publish(draft.copyWith(archivedTreatmentPlanIds: {...draft.archivedTreatmentPlanIds}..remove(id)));
        }
      }

      for (final plan in [...draft.pendingTreatmentPlans]) {
        await repository.createTreatmentPlan(
          visitId: visit.id,
          medicationName: plan.medicationName,
          medicationId: plan.medicationId,
          dosage: plan.dosage ?? '',
          frequency: plan.frequency ?? '',
          duration: plan.duration ?? '',
          notes: plan.notes,
        );
        publish(
          draft.copyWith(
            pendingTreatmentPlans: draft.pendingTreatmentPlans.where((p) => p.id != plan.id).toList(),
          ),
        );
      }

      for (final entry in Map<String, TreatmentPlanItem>.from(draft.treatmentPlanUpdates).entries) {
        final treatmentPlanId = entry.key;
        final updated = draft.treatmentPlanUpdates[treatmentPlanId]!;
        if (!isVisitDraftId(treatmentPlanId)) {
          await repository.updateTreatmentPlan(
            treatmentPlanId: treatmentPlanId,
            medicationName: updated.medicationName,
            medicationId: updated.medicationId,
            dosage: updated.dosage,
            frequency: updated.frequency,
            duration: updated.duration,
            notes: updated.notes,
          );
          final nextUpdates = Map.of(draft.treatmentPlanUpdates)..remove(treatmentPlanId);
          publish(draft.copyWith(treatmentPlanUpdates: nextUpdates));
        }
      }

      if (draft.pendingAttachments.isNotEmpty) {
        if (organizationId == null || organizationId.isEmpty) {
          throw StateError('Organization context is required to upload attachments.');
        }
        for (final pending in [...draft.pendingAttachments]) {
          await attachmentService.uploadAndRegister(
            organizationId: organizationId,
            branchId: visit.branchId,
            visitId: visit.id,
            pick: pending.pick,
            label: pending.label,
          );
          publish(
            draft.copyWith(
              pendingAttachments: draft.pendingAttachments.where((a) => a.id != pending.id).toList(),
            ),
          );
        }
      }

      for (final id in [...draft.deletedAttachmentIds]) {
        if (!isVisitDraftId(id)) {
          await repository.deleteVisitAttachment(attachmentId: id);
          publish(draft.copyWith(deletedAttachmentIds: {...draft.deletedAttachmentIds}..remove(id)));
        }
      }

      final patientId = visit.patientId;

      for (final id in [...draft.patientSafety.archivedAllergyIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archivePatientAllergy(allergyId: id);
          final safety = draft.patientSafety;
          publish(
            draft.copyWith(
              patientSafety: safety.copyWith(
                archivedAllergyIds: {...safety.archivedAllergyIds}..remove(id),
              ),
            ),
          );
        }
      }

      for (final allergy in [...draft.patientSafety.pendingAllergies]) {
        await repository.createPatientAllergy(
          patientId: patientId,
          substance: allergy.substance,
          reaction: allergy.reaction,
        );
        final safety = draft.patientSafety;
        publish(
          draft.copyWith(
            patientSafety: safety.copyWith(
              pendingAllergies: safety.pendingAllergies.where((a) => a.id != allergy.id).toList(),
            ),
          ),
        );
      }

      for (final entry in Map<String, PatientAllergy>.from(draft.patientSafety.allergyUpdates).entries) {
        final allergyId = entry.key;
        final updated = entry.value;
        if (!isVisitDraftId(allergyId)) {
          await repository.updatePatientAllergy(
            allergyId: allergyId,
            substance: updated.substance,
            reaction: updated.reaction,
          );
          final safety = draft.patientSafety;
          final nextUpdates = Map<String, PatientAllergy>.from(safety.allergyUpdates)..remove(allergyId);
          publish(draft.copyWith(patientSafety: safety.copyWith(allergyUpdates: nextUpdates)));
        }
      }

      for (final id in [...draft.patientSafety.archivedMedicationIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archivePatientMedication(medicationRecordId: id);
          final safety = draft.patientSafety;
          publish(
            draft.copyWith(
              patientSafety: safety.copyWith(
                archivedMedicationIds: {...safety.archivedMedicationIds}..remove(id),
              ),
            ),
          );
        }
      }

      for (final med in [...draft.patientSafety.pendingMedications]) {
        await repository.createPatientMedication(
          patientId: patientId,
          name: med.name,
          medicationId: med.medicationId,
          note: med.note,
        );
        final safety = draft.patientSafety;
        publish(
          draft.copyWith(
            patientSafety: safety.copyWith(
              pendingMedications: safety.pendingMedications.where((m) => m.id != med.id).toList(),
            ),
          ),
        );
      }

      for (final entry in Map<String, PatientMedication>.from(draft.patientSafety.medicationUpdates).entries) {
        final medicationRecordId = entry.key;
        final updated = entry.value;
        if (!isVisitDraftId(medicationRecordId)) {
          await repository.updatePatientMedication(
            medicationRecordId: medicationRecordId,
            name: updated.name,
            medicationId: updated.medicationId,
            note: updated.note,
          );
          final safety = draft.patientSafety;
          final nextUpdates = Map<String, PatientMedication>.from(safety.medicationUpdates)..remove(medicationRecordId);
          publish(draft.copyWith(patientSafety: safety.copyWith(medicationUpdates: nextUpdates)));
        }
      }

      for (final id in [...draft.patientSafety.archivedConditionIds]) {
        if (!isVisitDraftId(id)) {
          await repository.archivePatientChronicCondition(conditionId: id);
          final safety = draft.patientSafety;
          publish(
            draft.copyWith(
              patientSafety: safety.copyWith(
                archivedConditionIds: {...safety.archivedConditionIds}..remove(id),
              ),
            ),
          );
        }
      }

      for (final condition in [...draft.patientSafety.pendingConditions]) {
        await repository.createPatientChronicCondition(
          patientId: patientId,
          name: condition.name,
          note: condition.note,
        );
        final safety = draft.patientSafety;
        publish(
          draft.copyWith(
            patientSafety: safety.copyWith(
              pendingConditions: safety.pendingConditions.where((c) => c.id != condition.id).toList(),
            ),
          ),
        );
      }

      for (final entry in Map<String, PatientChronicCondition>.from(draft.patientSafety.conditionUpdates).entries) {
        final conditionId = entry.key;
        final updated = entry.value;
        if (!isVisitDraftId(conditionId)) {
          await repository.updatePatientChronicCondition(
            conditionId: conditionId,
            name: updated.name,
            note: updated.note,
          );
          final safety = draft.patientSafety;
          final nextUpdates = Map<String, PatientChronicCondition>.from(safety.conditionUpdates)..remove(conditionId);
          publish(draft.copyWith(patientSafety: safety.copyWith(conditionUpdates: nextUpdates)));
        }
      }

      return VisitEncounterFlushResult(success: true, remainingDraft: draft);
    } on RpcFailure catch (error) {
      return VisitEncounterFlushResult(success: false, remainingDraft: draft, error: error);
    } catch (error) {
      return VisitEncounterFlushResult(success: false, remainingDraft: draft, error: error);
    }
  }
}
