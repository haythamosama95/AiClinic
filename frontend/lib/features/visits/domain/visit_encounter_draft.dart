import 'dart:math';

import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter/foundation.dart';

/// Prefix for client-generated ids held only in the encounter draft.
const visitDraftIdPrefix = 'draft:';

bool isVisitDraftId(String id) => id.startsWith(visitDraftIdPrefix);

int _visitDraftIdCounter = 0;
final _visitDraftIdRandom = Random();

String newVisitDraftId() {
  final counter = _visitDraftIdCounter++;
  final entropy = _visitDraftIdRandom.nextInt(0xFFFFFF);
  return '$visitDraftIdPrefix${DateTime.now().microsecondsSinceEpoch}_${entropy}_$counter';
}

/// Attachment bytes staged locally until visit submit.
@immutable
class PendingVisitAttachment {
  const PendingVisitAttachment({
    required this.id,
    required this.pick,
    required this.label,
    required this.fileType,
    required this.uploadedBy,
    this.uploadedByName,
  });

  final String id;
  final VisitAttachmentPickInput pick;
  final String label;
  final VisitAttachmentFileType fileType;
  final String uploadedBy;
  final String? uploadedByName;

  VisitAttachmentItem toDisplayItem() {
    return VisitAttachmentItem(
      id: id,
      fileType: fileType,
      label: label,
      uploadedBy: uploadedBy,
      uploadedByName: uploadedByName,
      sizeBytes: pick.bytes.length,
      createdAt: DateTime.now().toUtc(),
      canDownload: true,
      canDelete: true,
    );
  }
}

/// Patient safety mutations staged until visit submit.
@immutable
class PatientSafetyDraft {
  const PatientSafetyDraft({
    this.pendingAllergies = const [],
    this.allergyUpdates = const {},
    this.archivedAllergyIds = const {},
    this.pendingMedications = const [],
    this.medicationUpdates = const {},
    this.archivedMedicationIds = const {},
    this.pendingConditions = const [],
    this.conditionUpdates = const {},
    this.archivedConditionIds = const {},
  });

  final List<PatientAllergy> pendingAllergies;
  final Map<String, PatientAllergy> allergyUpdates;
  final Set<String> archivedAllergyIds;
  final List<PatientMedication> pendingMedications;
  final Map<String, PatientMedication> medicationUpdates;
  final Set<String> archivedMedicationIds;
  final List<PatientChronicCondition> pendingConditions;
  final Map<String, PatientChronicCondition> conditionUpdates;
  final Set<String> archivedConditionIds;

  bool get isEmpty =>
      pendingAllergies.isEmpty &&
      allergyUpdates.isEmpty &&
      archivedAllergyIds.isEmpty &&
      pendingMedications.isEmpty &&
      medicationUpdates.isEmpty &&
      archivedMedicationIds.isEmpty &&
      pendingConditions.isEmpty &&
      conditionUpdates.isEmpty &&
      archivedConditionIds.isEmpty;

  PatientSafetyContext applyTo(PatientSafetyContext base) {
    return PatientSafetyContext(
      allergies: _mergeAllergies(base.allergies),
      currentMedications: _mergeMedications(base.currentMedications),
      chronicConditions: _mergeConditions(base.chronicConditions),
      lastVitals: base.lastVitals,
    );
  }

  List<PatientAllergy> _mergeAllergies(List<PatientAllergy> base) {
    final merged = <PatientAllergy>[
      for (final allergy in base)
        if (!archivedAllergyIds.contains(allergy.id)) allergyUpdates[allergy.id] ?? allergy,
      ...pendingAllergies,
    ];
    return merged;
  }

  List<PatientMedication> _mergeMedications(List<PatientMedication> base) {
    final merged = <PatientMedication>[
      for (final med in base)
        if (!archivedMedicationIds.contains(med.id)) medicationUpdates[med.id] ?? med,
      ...pendingMedications,
    ];
    return merged;
  }

  List<PatientChronicCondition> _mergeConditions(List<PatientChronicCondition> base) {
    final merged = <PatientChronicCondition>[
      for (final condition in base)
        if (!archivedConditionIds.contains(condition.id)) conditionUpdates[condition.id] ?? condition,
      ...pendingConditions,
    ];
    return merged;
  }
}

/// In-memory overlay for visit-scoped structured data until submit.
@immutable
class VisitEncounterDraft {
  const VisitEncounterDraft({
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
    this.pendingAttachments = const [],
    this.deletedAttachmentIds = const {},
    this.patientSafety = const PatientSafetyDraft(),
  });

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
  final List<PendingVisitAttachment> pendingAttachments;
  final Set<String> deletedAttachmentIds;
  final PatientSafetyDraft patientSafety;

  bool get isEmpty =>
      pendingVitalSigns.isEmpty &&
      vitalSignUpdates.isEmpty &&
      archivedVitalSignIds.isEmpty &&
      pendingInvestigations.isEmpty &&
      investigationUpdates.isEmpty &&
      archivedInvestigationIds.isEmpty &&
      pendingTreatmentPlans.isEmpty &&
      treatmentPlanUpdates.isEmpty &&
      archivedTreatmentPlanIds.isEmpty &&
      investigationResults.isEmpty &&
      pendingAttachments.isEmpty &&
      deletedAttachmentIds.isEmpty &&
      patientSafety.isEmpty;

  VisitDetail applyTo(VisitDetail visit) {
    return visit.copyWith(
      vitalSigns: _mergeVitalSigns(visit.vitalSigns),
      investigations: _mergeInvestigations(visit.investigations),
      treatmentPlans: _mergeTreatmentPlans(visit.treatmentPlans),
      attachments: _mergeAttachments(visit.attachments),
      pendingInvestigations: _mergePendingInvestigations(visit.pendingInvestigations),
    );
  }

  List<VisitVitalSign> _mergeVitalSigns(List<VisitVitalSign> base) {
    return [
      for (final sign in base)
        if (!archivedVitalSignIds.contains(sign.id)) vitalSignUpdates[sign.id] ?? sign,
      ...pendingVitalSigns,
    ];
  }

  List<VisitInvestigation> _mergeInvestigations(List<VisitInvestigation> base) {
    return [
      for (final investigation in base)
        if (!archivedInvestigationIds.contains(investigation.id))
          investigationUpdates[investigation.id] ?? investigation,
      ...pendingInvestigations,
    ];
  }

  List<TreatmentPlanItem> _mergeTreatmentPlans(List<TreatmentPlanItem> base) {
    return [
      for (final plan in base)
        if (!archivedTreatmentPlanIds.contains(plan.id)) treatmentPlanUpdates[plan.id] ?? plan,
      ...pendingTreatmentPlans,
    ];
  }

  List<VisitAttachmentItem> _mergeAttachments(List<VisitAttachmentItem> base) {
    return [
      for (final attachment in base)
        if (!deletedAttachmentIds.contains(attachment.id)) attachment,
      for (final pending in pendingAttachments) pending.toDisplayItem(),
    ];
  }

  List<VisitInvestigation> _mergePendingInvestigations(List<VisitInvestigation> base) {
    return [
      for (final investigation in base)
        if (!archivedInvestigationIds.contains(investigation.id))
          _withInvestigationResult(investigationUpdates[investigation.id] ?? investigation),
    ];
  }

  VisitInvestigation _withInvestigationResult(VisitInvestigation investigation) {
    final stagedResult = investigationResults[investigation.id];
    if (stagedResult == null) {
      return investigation;
    }
    return VisitInvestigation(
      id: investigation.id,
      name: investigation.name,
      note: investigation.note,
      investigationId: investigation.investigationId,
      result: stagedResult,
      resultRecordedAt: DateTime.now().toUtc(),
      orderedVisitId: investigation.orderedVisitId,
      orderedVisitDate: investigation.orderedVisitDate,
    );
  }

  PendingVisitAttachment? pendingAttachmentById(String id) {
    for (final pending in pendingAttachments) {
      if (pending.id == id) {
        return pending;
      }
    }
    return null;
  }

  Uint8List? pendingAttachmentBytes(String id) => pendingAttachmentById(id)?.pick.bytes;

  VisitEncounterDraft copyWith({
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
    List<PendingVisitAttachment>? pendingAttachments,
    Set<String>? deletedAttachmentIds,
    PatientSafetyDraft? patientSafety,
  }) {
    return VisitEncounterDraft(
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
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      deletedAttachmentIds: deletedAttachmentIds ?? this.deletedAttachmentIds,
      patientSafety: patientSafety ?? this.patientSafety,
    );
  }
}

extension PatientSafetyDraftCopy on PatientSafetyDraft {
  PatientSafetyDraft copyWith({
    List<PatientAllergy>? pendingAllergies,
    Map<String, PatientAllergy>? allergyUpdates,
    Set<String>? archivedAllergyIds,
    List<PatientMedication>? pendingMedications,
    Map<String, PatientMedication>? medicationUpdates,
    Set<String>? archivedMedicationIds,
    List<PatientChronicCondition>? pendingConditions,
    Map<String, PatientChronicCondition>? conditionUpdates,
    Set<String>? archivedConditionIds,
  }) {
    return PatientSafetyDraft(
      pendingAllergies: pendingAllergies ?? this.pendingAllergies,
      allergyUpdates: allergyUpdates ?? this.allergyUpdates,
      archivedAllergyIds: archivedAllergyIds ?? this.archivedAllergyIds,
      pendingMedications: pendingMedications ?? this.pendingMedications,
      medicationUpdates: medicationUpdates ?? this.medicationUpdates,
      archivedMedicationIds: archivedMedicationIds ?? this.archivedMedicationIds,
      pendingConditions: pendingConditions ?? this.pendingConditions,
      conditionUpdates: conditionUpdates ?? this.conditionUpdates,
      archivedConditionIds: archivedConditionIds ?? this.archivedConditionIds,
    );
  }
}
