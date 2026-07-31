import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

const encounterTestVisitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const encounterTestPatientId = '11111111-1111-4111-8111-111111111111';
const encounterTestBranchId = '44444444-4444-4444-8444-444444444444';

const encounterTestAppointmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const encounterTestDoctorId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

const encounterTestVitalSignId = 'ssssssss-ssss-4sss-8sss-ssssssssssss';
const encounterTestInvestigationLineId = 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn';
const encounterTestTreatmentPlanId = 'tttttttt-tttt-4ttt-8ttt-tttttttttttt';
const encounterTestAttachmentId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const encounterTestAllergyId = 'aaaaaaaa-aaaa-4aab-8aaa-aaaaaaaaaaaa';
const encounterTestMedicationRecordId = 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm';
const encounterTestConditionId = 'cccccccc-cccc-4ccd-8ccc-cccccccccccc';

VisitDetail sampleEncounterVisit({
  String? visitType,
  List<VisitVitalSign> vitalSigns = const [],
  String? id,
  String? branchId,
  String? appointmentId,
  String? patientId,
  String? doctorId,
  String? doctorName,
  DateTime? visitDate,
  VisitStatus? status,
  DateTime? updatedAt,
  VisitClinicalNote? documentation,
  List<VisitInvestigation>? investigations,
  List<TreatmentPlanItem>? treatmentPlans,
  List<VisitAttachmentItem>? attachments,
  List<VisitInvestigation>? pendingInvestigations,
}) {
  return VisitDetail(
    id: id ?? encounterTestVisitId,
    branchId: branchId ?? encounterTestBranchId,
    appointmentId: appointmentId ?? encounterTestAppointmentId,
    patientId: patientId ?? encounterTestPatientId,
    doctorId: doctorId ?? encounterTestDoctorId,
    doctorName: doctorName ?? 'Dr Test',
    visitDate: visitDate ?? DateTime.utc(2026, 5, 31),
    status: status ?? VisitStatus.inProgress,
    visitType: visitType,
    updatedAt: updatedAt ?? DateTime.utc(2026, 5, 31, 10),
    documentation: documentation,
    vitalSigns: vitalSigns,
    investigations: investigations ?? const [],
    treatmentPlans: treatmentPlans ?? const [],
    attachments: attachments ?? const [],
    pendingInvestigations: pendingInvestigations ?? const [],
  );
}

VisitDocumentationState sampleEncounterDocState({
  VisitDetail? visit,
  VisitDetail? persistedVisit,
  String? complaint,
  String? history,
  String? examination,
  String? diagnosis,
  String? plan,
  DateTime? expectedUpdatedAt,
  Map<ClinicalNoteSection, List<dynamic>>? richTextDrafts,
  List<CatalogItem>? predefinedVitalSigns,
  VisitEncounterDraft? encounterDraft,
  DocumentationSaveStatus? saveStatus,
  DocumentationEditMode? noteEditMode,
  WorkspaceEditMode? workspaceEditMode,
  String? errorMessage,
  bool clearError = false,
}) {
  final resolved = visit ?? sampleEncounterVisit();
  return VisitDocumentationState(
    visit: resolved,
    persistedVisit: persistedVisit ?? resolved,
    complaint: complaint ?? '',
    history: history ?? '',
    examination: examination ?? '',
    diagnosis: diagnosis ?? '',
    plan: plan ?? '',
    expectedUpdatedAt: expectedUpdatedAt ?? resolved.updatedAt ?? resolved.visitDate,
    richTextDrafts: richTextDrafts ?? const {},
    predefinedVitalSigns: predefinedVitalSigns ?? const [],
    encounterDraft: encounterDraft ?? const VisitEncounterDraft(),
    saveStatus: saveStatus ?? DocumentationSaveStatus.idle,
    noteEditMode: noteEditMode ?? DocumentationEditMode.editing,
    workspaceEditMode: workspaceEditMode ?? WorkspaceEditMode.editing,
    errorMessage: clearError ? null : errorMessage,
  );
}

VisitVitalSign buildVisitVitalSign({
  String id = encounterTestVitalSignId,
  String name = 'Blood Pressure',
  String value = '120/80',
  String? unit = 'mmHg',
  String? predefinedVitalSignId,
}) {
  return VisitVitalSign(
    id: id,
    name: name,
    value: value,
    unit: unit,
    predefinedVitalSignId: predefinedVitalSignId,
  );
}

VisitInvestigation buildVisitInvestigation({
  String id = encounterTestInvestigationLineId,
  String name = 'Complete Blood Count',
  String? note,
  String? investigationId,
  String? result,
  DateTime? resultRecordedAt,
  String? orderedVisitId,
  DateTime? orderedVisitDate,
}) {
  return VisitInvestigation(
    id: id,
    name: name,
    note: note,
    investigationId: investigationId,
    result: result,
    resultRecordedAt: resultRecordedAt,
    orderedVisitId: orderedVisitId,
    orderedVisitDate: orderedVisitDate,
  );
}

TreatmentPlanItem buildVisitTreatmentPlanItem({
  String id = encounterTestTreatmentPlanId,
  String visitId = encounterTestVisitId,
  String patientId = encounterTestPatientId,
  String medicationName = 'Amoxicillin',
  String? medicationId,
  String? dosage,
  String? frequency,
  String? duration,
  String? notes,
}) {
  return TreatmentPlanItem(
    id: id,
    visitId: visitId,
    patientId: patientId,
    medicationName: medicationName,
    medicationId: medicationId,
    dosage: dosage,
    frequency: frequency,
    duration: duration,
    notes: notes,
  );
}

VisitAttachmentItem buildVisitAttachmentItem({
  String id = encounterTestAttachmentId,
  VisitAttachmentFileType fileType = VisitAttachmentFileType.pdf,
  String? label = 'Lab PDF',
  String uploadedBy = encounterTestDoctorId,
  String? uploadedByName = 'Dr Test',
  int sizeBytes = 1024,
  DateTime? createdAt,
  bool canDownload = true,
  bool canDelete = true,
}) {
  return VisitAttachmentItem(
    id: id,
    fileType: fileType,
    label: label,
    uploadedBy: uploadedBy,
    uploadedByName: uploadedByName,
    sizeBytes: sizeBytes,
    createdAt: createdAt ?? DateTime.utc(2026, 5, 31, 10),
    canDownload: canDownload,
    canDelete: canDelete,
  );
}

VisitClinicalNote buildVisitClinicalNote({
  String? complaint,
  String? history,
  String? examination,
  String? diagnosis,
  String? plan,
  DateTime? updatedAt,
}) {
  return VisitClinicalNote(
    complaint: complaint,
    history: history,
    examination: examination,
    diagnosis: diagnosis,
    plan: plan,
    updatedAt: updatedAt ?? DateTime.utc(2026, 5, 31, 10),
  );
}

PatientAllergy buildPatientAllergy({
  String id = encounterTestAllergyId,
  String substance = 'Penicillin',
  String? reaction,
}) {
  return PatientAllergy(id: id, substance: substance, reaction: reaction);
}

PatientMedication buildPatientMedication({
  String id = encounterTestMedicationRecordId,
  String name = 'Metformin',
  String? medicationId,
  String? note,
}) {
  return PatientMedication(id: id, name: name, medicationId: medicationId, note: note);
}

PatientChronicCondition buildPatientChronicCondition({
  String id = encounterTestConditionId,
  String name = 'Type 2 diabetes',
  String? note,
}) {
  return PatientChronicCondition(id: id, name: name, note: note);
}

PatientSafetyContext buildPatientSafetyContext({
  List<PatientAllergy>? allergies,
  List<PatientMedication>? currentMedications,
  List<PatientChronicCondition>? chronicConditions,
  PatientSafetyLastVitals? lastVitals,
}) {
  return PatientSafetyContext(
    allergies: allergies ?? const [],
    currentMedications: currentMedications ?? const [],
    chronicConditions: chronicConditions ?? const [],
    lastVitals: lastVitals ?? const PatientSafetyLastVitals(),
  );
}

VisitEncounterDraft buildVisitEncounterDraft({
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
    pendingVitalSigns: pendingVitalSigns ?? const [],
    vitalSignUpdates: vitalSignUpdates ?? const {},
    archivedVitalSignIds: archivedVitalSignIds ?? const {},
    pendingInvestigations: pendingInvestigations ?? const [],
    investigationUpdates: investigationUpdates ?? const {},
    archivedInvestigationIds: archivedInvestigationIds ?? const {},
    pendingTreatmentPlans: pendingTreatmentPlans ?? const [],
    treatmentPlanUpdates: treatmentPlanUpdates ?? const {},
    archivedTreatmentPlanIds: archivedTreatmentPlanIds ?? const {},
    investigationResults: investigationResults ?? const {},
    pendingAttachments: pendingAttachments ?? const [],
    deletedAttachmentIds: deletedAttachmentIds ?? const {},
    patientSafety: patientSafety ?? const PatientSafetyDraft(),
  );
}

RpcFailure visitsRpcFailure({String code = 'NOT_FOUND', String message = 'Visit not found.'}) {
  return RpcFailure(
    RpcResult(success: false, errorCode: code, errorMessage: message),
  );
}
