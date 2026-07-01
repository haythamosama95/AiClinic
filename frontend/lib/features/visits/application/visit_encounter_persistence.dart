import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Routes visit mutations either to the in-memory encounter draft or directly to the backend.
class VisitEncounterPersistence {
  VisitEncounterPersistence(this.ref, {required this.visitId, required this.deferPersistence});

  final WidgetRef ref;
  final String visitId;
  final bool deferPersistence;

  VisitDocumentationNotifier get _notifier => ref.read(visitDocumentationProvider(visitId).notifier);

  Future<void> createVisitVitalSign({
    required String name,
    required String value,
    String? unit,
    String? predefinedVitalSignId,
  }) async {
    if (deferPersistence) {
      _notifier.stageCreateVitalSign(
        name: name,
        value: value,
        unit: unit,
        predefinedVitalSignId: predefinedVitalSignId,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .createVisitVitalSign(
          visitId: visitId,
          name: name,
          value: value,
          unit: unit,
          predefinedVitalSignId: predefinedVitalSignId,
        );
  }

  Future<void> updateVisitVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) async {
    if (deferPersistence) {
      _notifier.stageUpdateVitalSign(
        vitalSignId: vitalSignId,
        name: name,
        value: value,
        unit: unit,
        predefinedVitalSignId: predefinedVitalSignId,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updateVisitVitalSign(
          vitalSignId: vitalSignId,
          name: name,
          value: value,
          unit: unit,
          predefinedVitalSignId: predefinedVitalSignId,
        );
  }

  Future<void> archiveVisitVitalSign({required String vitalSignId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveVitalSign(vitalSignId);
      return;
    }
    await ref.read(visitRepositoryProvider).archiveVisitVitalSign(vitalSignId: vitalSignId);
  }

  Future<void> createVisitInvestigation({required String name, String? note, String? investigationId}) async {
    if (deferPersistence) {
      _notifier.stageCreateInvestigation(name: name, note: note, investigationId: investigationId);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .createVisitInvestigation(visitId: visitId, name: name, note: note, investigationId: investigationId);
  }

  Future<void> updateVisitInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
  }) async {
    if (deferPersistence) {
      _notifier.stageUpdateInvestigation(
        investigationLineId: investigationLineId,
        name: name,
        note: note,
        investigationId: investigationId,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updateVisitInvestigation(
          investigationLineId: investigationLineId,
          name: name,
          note: note,
          investigationId: investigationId,
        );
  }

  Future<void> archiveVisitInvestigation({required String investigationLineId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveInvestigation(investigationLineId);
      return;
    }
    await ref.read(visitRepositoryProvider).archiveVisitInvestigation(investigationLineId: investigationLineId);
  }

  Future<void> recordInvestigationResult({required String investigationLineId, required String result}) async {
    if (deferPersistence) {
      _notifier.stageInvestigationResult(investigationLineId: investigationLineId, result: result);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .recordInvestigationResult(investigationLineId: investigationLineId, result: result);
  }

  Future<void> createTreatmentPlan({
    required String medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) async {
    if (deferPersistence) {
      _notifier.stageCreateTreatmentPlan(
        medicationName: medicationName,
        medicationId: medicationId,
        dosage: dosage,
        frequency: frequency,
        duration: duration,
        notes: notes,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .createTreatmentPlan(
          visitId: visitId,
          medicationName: medicationName,
          medicationId: medicationId,
          dosage: dosage ?? '',
          frequency: frequency ?? '',
          duration: duration ?? '',
          notes: notes,
        );
  }

  Future<void> updateTreatmentPlan({
    required String treatmentPlanId,
    String? medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) async {
    if (deferPersistence) {
      _notifier.stageUpdateTreatmentPlan(
        treatmentPlanId: treatmentPlanId,
        medicationName: medicationName,
        medicationId: medicationId,
        dosage: dosage,
        frequency: frequency,
        duration: duration,
        notes: notes,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updateTreatmentPlan(
          treatmentPlanId: treatmentPlanId,
          medicationName: medicationName,
          medicationId: medicationId,
          dosage: dosage,
          frequency: frequency,
          duration: duration,
          notes: notes,
        );
  }

  Future<void> archiveTreatmentPlan({required String treatmentPlanId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveTreatmentPlan(treatmentPlanId);
      return;
    }
    await ref.read(visitRepositoryProvider).archiveTreatmentPlan(treatmentPlanId: treatmentPlanId);
  }

  Future<void> stageAttachment({
    required VisitAttachmentPickInput pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  }) async {
    if (deferPersistence) {
      _notifier.stageAttachment(pick: pick, label: label, uploadedBy: uploadedBy, uploadedByName: uploadedByName);
      return;
    }
    throw StateError('stageAttachment requires deferPersistence.');
  }

  Future<void> uploadAndRegisterAttachment({
    required String organizationId,
    required String branchId,
    required VisitAttachmentPickInput pick,
    required String label,
  }) async {
    if (deferPersistence) {
      throw StateError('uploadAndRegisterAttachment is not used when deferPersistence is true.');
    }
    await ref
        .read(visitAttachmentServiceProvider)
        .uploadAndRegister(
          organizationId: organizationId,
          branchId: branchId,
          visitId: visitId,
          pick: pick,
          label: label,
        );
  }

  Future<void> deleteVisitAttachment({required String attachmentId}) async {
    if (deferPersistence) {
      _notifier.stageDeleteAttachment(attachmentId);
      return;
    }
    await ref.read(visitRepositoryProvider).deleteVisitAttachment(attachmentId: attachmentId);
  }

  Future<void> createPatientAllergy({required String patientId, required String substance, String? reaction}) async {
    if (deferPersistence) {
      _notifier.stageCreateAllergy(substance: substance, reaction: reaction);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .createPatientAllergy(patientId: patientId, substance: substance, reaction: reaction);
  }

  Future<void> updatePatientAllergy({required String allergyId, String? substance, String? reaction}) async {
    if (deferPersistence) {
      _notifier.stageUpdateAllergy(allergyId: allergyId, substance: substance, reaction: reaction);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updatePatientAllergy(allergyId: allergyId, substance: substance, reaction: reaction);
  }

  Future<void> archivePatientAllergy({required String allergyId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveAllergy(allergyId);
      return;
    }
    await ref.read(visitRepositoryProvider).archivePatientAllergy(allergyId: allergyId);
  }

  Future<void> createPatientMedication({
    required String patientId,
    required String name,
    String? medicationId,
    String? note,
  }) async {
    if (deferPersistence) {
      _notifier.stageCreateMedication(name: name, medicationId: medicationId, note: note);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .createPatientMedication(patientId: patientId, name: name, medicationId: medicationId, note: note);
  }

  Future<void> updatePatientMedication({
    required String medicationRecordId,
    String? name,
    String? medicationId,
    String? note,
  }) async {
    if (deferPersistence) {
      _notifier.stageUpdateMedication(
        medicationRecordId: medicationRecordId,
        name: name,
        medicationId: medicationId,
        note: note,
      );
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updatePatientMedication(
          medicationRecordId: medicationRecordId,
          name: name,
          medicationId: medicationId,
          note: note,
        );
  }

  Future<void> archivePatientMedication({required String medicationRecordId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveMedication(medicationRecordId);
      return;
    }
    await ref.read(visitRepositoryProvider).archivePatientMedication(medicationRecordId: medicationRecordId);
  }

  Future<void> createPatientChronicCondition({required String patientId, required String name, String? note}) async {
    if (deferPersistence) {
      _notifier.stageCreateCondition(name: name, note: note);
      return;
    }
    await ref.read(visitRepositoryProvider).createPatientChronicCondition(patientId: patientId, name: name, note: note);
  }

  Future<void> updatePatientChronicCondition({required String conditionId, String? name, String? note}) async {
    if (deferPersistence) {
      _notifier.stageUpdateCondition(conditionId: conditionId, name: name, note: note);
      return;
    }
    await ref
        .read(visitRepositoryProvider)
        .updatePatientChronicCondition(conditionId: conditionId, name: name, note: note);
  }

  Future<void> archivePatientChronicCondition({required String conditionId}) async {
    if (deferPersistence) {
      _notifier.stageArchiveCondition(conditionId);
      return;
    }
    await ref.read(visitRepositoryProvider).archivePatientChronicCondition(conditionId: conditionId);
  }

  PatientSafetyContext effectivePatientSafety(PatientSafetyContext base) {
    if (!deferPersistence) {
      return base;
    }
    return ref.read(visitDocumentationProvider(visitId)).value?.effectivePatientSafety(base) ?? base;
  }
}

VisitEncounterPersistence visitEncounterPersistence(
  WidgetRef ref, {
  required String visitId,
  required bool deferPersistence,
}) {
  return VisitEncounterPersistence(ref, visitId: visitId, deferPersistence: deferPersistence);
}
