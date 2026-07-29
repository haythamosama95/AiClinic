// Test-only harness for visit page widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod/misc.dart' show Override;

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

export 'package:riverpod/misc.dart' show Override;
export '../../support/visit_encounter_test_support.dart';

const visitsWideSurfaceSize = Size(1400, 1000);

/// Fixed documentation state that records mutation calls for widget assertions.
class StubVisitDocumentationNotifier extends VisitDocumentationNotifier {
  StubVisitDocumentationNotifier(
    super.visitId,
    VisitDocumentationState initialState, {
    this.onSave,
    this.onSaveAll,
    this.onCompleteVisit,
    this.completeVisitError,
  })  : _state = initialState;

  VisitDocumentationState _state;
  final Future<void> Function()? onSave;
  final Future<bool> Function()? onSaveAll;
  final Future<CompleteVisitResult> Function()? onCompleteVisit;
  final Object? completeVisitError;

  var saveCallCount = 0;
  var saveAllCallCount = 0;
  var completeVisitCallCount = 0;
  var enterEditModeCallCount = 0;
  var enterWorkspaceEditModeCallCount = 0;
  var reloadVisitCallCount = 0;
  var refreshVisitPreservingDraftCallCount = 0;

  var stageCreateVitalSignCallCount = 0;
  String? lastStageCreateVitalSignName;
  String? lastStageCreateVitalSignValue;
  String? lastStageCreateVitalSignUnit;
  String? lastStageCreateVitalSignPredefinedId;

  var stageUpdateVitalSignCallCount = 0;
  String? lastStageUpdateVitalSignId;
  String? lastStageUpdateVitalSignName;
  String? lastStageUpdateVitalSignValue;
  String? lastStageUpdateVitalSignUnit;
  String? lastStageUpdateVitalSignPredefinedId;

  var stageArchiveVitalSignCallCount = 0;
  String? lastStageArchiveVitalSignId;

  var stageCreateInvestigationCallCount = 0;
  String? lastStageCreateInvestigationName;
  String? lastStageCreateInvestigationNote;
  String? lastStageCreateInvestigationCatalogId;

  var stageUpdateInvestigationCallCount = 0;
  String? lastStageUpdateInvestigationLineId;
  String? lastStageUpdateInvestigationName;
  String? lastStageUpdateInvestigationNote;
  String? lastStageUpdateInvestigationCatalogId;
  bool lastStageUpdateInvestigationIdFlag = false;

  var stageArchiveInvestigationCallCount = 0;
  String? lastStageArchiveInvestigationLineId;

  var stageInvestigationResultCallCount = 0;
  String? lastStageInvestigationResultLineId;
  String? lastStageInvestigationResultValue;

  var stageCreateTreatmentPlanCallCount = 0;
  String? lastStageCreateTreatmentPlanMedicationName;
  String? lastStageCreateTreatmentPlanMedicationId;
  String? lastStageCreateTreatmentPlanDosage;
  String? lastStageCreateTreatmentPlanFrequency;
  String? lastStageCreateTreatmentPlanDuration;
  String? lastStageCreateTreatmentPlanNotes;

  var stageUpdateTreatmentPlanCallCount = 0;
  String? lastStageUpdateTreatmentPlanId;
  String? lastStageUpdateTreatmentPlanMedicationName;
  String? lastStageUpdateTreatmentPlanMedicationId;
  String? lastStageUpdateTreatmentPlanDosage;
  String? lastStageUpdateTreatmentPlanFrequency;
  String? lastStageUpdateTreatmentPlanDuration;
  String? lastStageUpdateTreatmentPlanNotes;

  var stageArchiveTreatmentPlanCallCount = 0;
  String? lastStageArchiveTreatmentPlanId;

  var stageAttachmentCallCount = 0;
  VisitAttachmentPickInput? lastStageAttachmentPick;
  String? lastStageAttachmentLabel;
  String? lastStageAttachmentUploadedBy;
  String? lastStageAttachmentUploadedByName;

  var stageDeleteAttachmentCallCount = 0;
  String? lastStageDeleteAttachmentId;

  var stageCreateAllergyCallCount = 0;
  String? lastStageCreateAllergySubstance;
  String? lastStageCreateAllergyReaction;

  var stageUpdateAllergyCallCount = 0;
  String? lastStageUpdateAllergyId;
  String? lastStageUpdateAllergySubstance;
  String? lastStageUpdateAllergyReaction;

  var stageArchiveAllergyCallCount = 0;
  String? lastStageArchiveAllergyId;

  var stageCreateMedicationCallCount = 0;
  String? lastStageCreateMedicationName;
  String? lastStageCreateMedicationCatalogId;
  String? lastStageCreateMedicationNote;

  var stageUpdateMedicationCallCount = 0;
  String? lastStageUpdateMedicationRecordId;
  String? lastStageUpdateMedicationName;
  String? lastStageUpdateMedicationCatalogId;
  String? lastStageUpdateMedicationNote;

  var stageArchiveMedicationCallCount = 0;
  String? lastStageArchiveMedicationRecordId;

  var stageCreateConditionCallCount = 0;
  String? lastStageCreateConditionName;
  String? lastStageCreateConditionNote;

  var stageUpdateConditionCallCount = 0;
  String? lastStageUpdateConditionId;
  String? lastStageUpdateConditionName;
  String? lastStageUpdateConditionNote;

  var stageArchiveConditionCallCount = 0;
  String? lastStageArchiveConditionId;

  String? lastUpdateComplaint;
  List<dynamic>? lastUpdateComplaintRichDelta;
  String? lastUpdateHistory;
  List<dynamic>? lastUpdateHistoryRichDelta;
  String? lastUpdateExamination;
  List<dynamic>? lastUpdateExaminationRichDelta;
  String? lastUpdateDiagnosis;
  List<dynamic>? lastUpdateDiagnosisRichDelta;
  String? lastUpdatePlan;
  List<dynamic>? lastUpdatePlanRichDelta;

  var updateComplaintCallCount = 0;
  var updateHistoryCallCount = 0;
  var updateExaminationCallCount = 0;
  var updateDiagnosisCallCount = 0;
  var updatePlanCallCount = 0;

  @override
  Future<VisitDocumentationState> build() async => _state;

  void replaceState(VisitDocumentationState next) {
    _state = next;
    state = AsyncData(next);
  }

  void _syncFromState() {
    final current = state.value;
    if (current != null) {
      _state = current;
    }
  }

  @override
  Future<void> save() async {
    saveCallCount++;
    if (onSave != null) {
      await onSave!();
      return;
    }
  }

  @override
  Future<bool> saveAll() async {
    saveAllCallCount++;
    if (onSaveAll != null) {
      return onSaveAll!();
    }
    return true;
  }

  @override
  Future<CompleteVisitResult> completeVisit({DateTime? expectedUpdatedAt}) async {
    completeVisitCallCount++;
    if (completeVisitError != null) {
      throw completeVisitError!;
    }
    if (onCompleteVisit != null) {
      return onCompleteVisit!();
    }

    _syncFromState();
    final completed = _state.visit.copyWith(status: VisitStatus.completed);
    replaceState(
      _state.copyWith(
        visit: completed,
        persistedVisit: completed,
        workspaceEditMode: WorkspaceEditMode.viewing,
        noteEditMode: DocumentationEditMode.readOnly,
        saveStatus: DocumentationSaveStatus.saved,
      ),
    );
    return const CompleteVisitResult(
      visitId: encounterTestVisitId,
      visitStatus: 'completed',
      appointmentId: encounterTestAppointmentId,
      appointmentStatus: 'completed',
    );
  }

  @override
  void updateComplaint(String value, {List<dynamic>? richDelta}) {
    updateComplaintCallCount++;
    lastUpdateComplaint = value;
    lastUpdateComplaintRichDelta = richDelta;
    super.updateComplaint(value, richDelta: richDelta);
  }

  @override
  void updateHistory(String value, {List<dynamic>? richDelta}) {
    updateHistoryCallCount++;
    lastUpdateHistory = value;
    lastUpdateHistoryRichDelta = richDelta;
    super.updateHistory(value, richDelta: richDelta);
  }

  @override
  void updateExamination(String value, {List<dynamic>? richDelta}) {
    updateExaminationCallCount++;
    lastUpdateExamination = value;
    lastUpdateExaminationRichDelta = richDelta;
    super.updateExamination(value, richDelta: richDelta);
  }

  @override
  void updateDiagnosis(String value, {List<dynamic>? richDelta}) {
    updateDiagnosisCallCount++;
    lastUpdateDiagnosis = value;
    lastUpdateDiagnosisRichDelta = richDelta;
    super.updateDiagnosis(value, richDelta: richDelta);
  }

  @override
  void updatePlan(String value, {List<dynamic>? richDelta}) {
    updatePlanCallCount++;
    lastUpdatePlan = value;
    lastUpdatePlanRichDelta = richDelta;
    super.updatePlan(value, richDelta: richDelta);
  }

  @override
  void enterEditMode() {
    enterEditModeCallCount++;
    super.enterEditMode();
  }

  @override
  void enterWorkspaceEditMode() {
    enterWorkspaceEditModeCallCount++;
    super.enterWorkspaceEditMode();
  }

  @override
  Future<void> reloadVisit() async {
    reloadVisitCallCount++;
  }

  @override
  Future<void> refreshVisitPreservingDraft() async {
    refreshVisitPreservingDraftCallCount++;
  }

  @override
  void stageCreateVitalSign({
    required String name,
    required String value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    stageCreateVitalSignCallCount++;
    lastStageCreateVitalSignName = name;
    lastStageCreateVitalSignValue = value;
    lastStageCreateVitalSignUnit = unit;
    lastStageCreateVitalSignPredefinedId = predefinedVitalSignId;
    super.stageCreateVitalSign(
      name: name,
      value: value,
      unit: unit,
      predefinedVitalSignId: predefinedVitalSignId,
    );
  }

  @override
  void stageUpdateVitalSign({
    required String vitalSignId,
    String? name,
    String? value,
    String? unit,
    String? predefinedVitalSignId,
  }) {
    stageUpdateVitalSignCallCount++;
    lastStageUpdateVitalSignId = vitalSignId;
    lastStageUpdateVitalSignName = name;
    lastStageUpdateVitalSignValue = value;
    lastStageUpdateVitalSignUnit = unit;
    lastStageUpdateVitalSignPredefinedId = predefinedVitalSignId;
    super.stageUpdateVitalSign(
      vitalSignId: vitalSignId,
      name: name,
      value: value,
      unit: unit,
      predefinedVitalSignId: predefinedVitalSignId,
    );
  }

  @override
  void stageArchiveVitalSign(String vitalSignId) {
    stageArchiveVitalSignCallCount++;
    lastStageArchiveVitalSignId = vitalSignId;
    super.stageArchiveVitalSign(vitalSignId);
  }

  @override
  void stageCreateInvestigation({required String name, String? note, String? investigationId}) {
    stageCreateInvestigationCallCount++;
    lastStageCreateInvestigationName = name;
    lastStageCreateInvestigationNote = note;
    lastStageCreateInvestigationCatalogId = investigationId;
    super.stageCreateInvestigation(name: name, note: note, investigationId: investigationId);
  }

  @override
  void stageUpdateInvestigation({
    required String investigationLineId,
    String? name,
    String? note,
    String? investigationId,
    bool updateInvestigationId = false,
  }) {
    stageUpdateInvestigationCallCount++;
    lastStageUpdateInvestigationLineId = investigationLineId;
    lastStageUpdateInvestigationName = name;
    lastStageUpdateInvestigationNote = note;
    lastStageUpdateInvestigationCatalogId = investigationId;
    lastStageUpdateInvestigationIdFlag = updateInvestigationId;
    super.stageUpdateInvestigation(
      investigationLineId: investigationLineId,
      name: name,
      note: note,
      investigationId: investigationId,
      updateInvestigationId: updateInvestigationId,
    );
  }

  @override
  void stageArchiveInvestigation(String investigationLineId) {
    stageArchiveInvestigationCallCount++;
    lastStageArchiveInvestigationLineId = investigationLineId;
    super.stageArchiveInvestigation(investigationLineId);
  }

  @override
  void stageInvestigationResult({required String investigationLineId, required String result}) {
    stageInvestigationResultCallCount++;
    lastStageInvestigationResultLineId = investigationLineId;
    lastStageInvestigationResultValue = result;
    super.stageInvestigationResult(investigationLineId: investigationLineId, result: result);
  }

  @override
  void stageCreateTreatmentPlan({
    required String medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) {
    stageCreateTreatmentPlanCallCount++;
    lastStageCreateTreatmentPlanMedicationName = medicationName;
    lastStageCreateTreatmentPlanMedicationId = medicationId;
    lastStageCreateTreatmentPlanDosage = dosage;
    lastStageCreateTreatmentPlanFrequency = frequency;
    lastStageCreateTreatmentPlanDuration = duration;
    lastStageCreateTreatmentPlanNotes = notes;
    super.stageCreateTreatmentPlan(
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
  }

  @override
  void stageUpdateTreatmentPlan({
    required String treatmentPlanId,
    String? medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  }) {
    stageUpdateTreatmentPlanCallCount++;
    lastStageUpdateTreatmentPlanId = treatmentPlanId;
    lastStageUpdateTreatmentPlanMedicationName = medicationName;
    lastStageUpdateTreatmentPlanMedicationId = medicationId;
    lastStageUpdateTreatmentPlanDosage = dosage;
    lastStageUpdateTreatmentPlanFrequency = frequency;
    lastStageUpdateTreatmentPlanDuration = duration;
    lastStageUpdateTreatmentPlanNotes = notes;
    super.stageUpdateTreatmentPlan(
      treatmentPlanId: treatmentPlanId,
      medicationName: medicationName,
      medicationId: medicationId,
      dosage: dosage,
      frequency: frequency,
      duration: duration,
      notes: notes,
    );
  }

  @override
  void stageArchiveTreatmentPlan(String treatmentPlanId) {
    stageArchiveTreatmentPlanCallCount++;
    lastStageArchiveTreatmentPlanId = treatmentPlanId;
    super.stageArchiveTreatmentPlan(treatmentPlanId);
  }

  @override
  void stageAttachment({
    required VisitAttachmentPickInput pick,
    required String label,
    required String uploadedBy,
    String? uploadedByName,
  }) {
    stageAttachmentCallCount++;
    lastStageAttachmentPick = pick;
    lastStageAttachmentLabel = label;
    lastStageAttachmentUploadedBy = uploadedBy;
    lastStageAttachmentUploadedByName = uploadedByName;
    super.stageAttachment(
      pick: pick,
      label: label,
      uploadedBy: uploadedBy,
      uploadedByName: uploadedByName,
    );
  }

  @override
  void stageDeleteAttachment(String attachmentId) {
    stageDeleteAttachmentCallCount++;
    lastStageDeleteAttachmentId = attachmentId;
    super.stageDeleteAttachment(attachmentId);
  }

  @override
  void stageCreateAllergy({required String substance, String? reaction}) {
    stageCreateAllergyCallCount++;
    lastStageCreateAllergySubstance = substance;
    lastStageCreateAllergyReaction = reaction;
    super.stageCreateAllergy(substance: substance, reaction: reaction);
  }

  @override
  void stageUpdateAllergy({required String allergyId, String? substance, String? reaction}) {
    stageUpdateAllergyCallCount++;
    lastStageUpdateAllergyId = allergyId;
    lastStageUpdateAllergySubstance = substance;
    lastStageUpdateAllergyReaction = reaction;
    super.stageUpdateAllergy(allergyId: allergyId, substance: substance, reaction: reaction);
  }

  @override
  void stageArchiveAllergy(String allergyId) {
    stageArchiveAllergyCallCount++;
    lastStageArchiveAllergyId = allergyId;
    super.stageArchiveAllergy(allergyId);
  }

  @override
  void stageCreateMedication({required String name, String? medicationId, String? note}) {
    stageCreateMedicationCallCount++;
    lastStageCreateMedicationName = name;
    lastStageCreateMedicationCatalogId = medicationId;
    lastStageCreateMedicationNote = note;
    super.stageCreateMedication(name: name, medicationId: medicationId, note: note);
  }

  @override
  void stageUpdateMedication({required String medicationRecordId, String? name, String? medicationId, String? note}) {
    stageUpdateMedicationCallCount++;
    lastStageUpdateMedicationRecordId = medicationRecordId;
    lastStageUpdateMedicationName = name;
    lastStageUpdateMedicationCatalogId = medicationId;
    lastStageUpdateMedicationNote = note;
    super.stageUpdateMedication(
      medicationRecordId: medicationRecordId,
      name: name,
      medicationId: medicationId,
      note: note,
    );
  }

  @override
  void stageArchiveMedication(String medicationRecordId) {
    stageArchiveMedicationCallCount++;
    lastStageArchiveMedicationRecordId = medicationRecordId;
    super.stageArchiveMedication(medicationRecordId);
  }

  @override
  void stageCreateCondition({required String name, String? note}) {
    stageCreateConditionCallCount++;
    lastStageCreateConditionName = name;
    lastStageCreateConditionNote = note;
    super.stageCreateCondition(name: name, note: note);
  }

  @override
  void stageUpdateCondition({required String conditionId, String? name, String? note}) {
    stageUpdateConditionCallCount++;
    lastStageUpdateConditionId = conditionId;
    lastStageUpdateConditionName = name;
    lastStageUpdateConditionNote = note;
    super.stageUpdateCondition(conditionId: conditionId, name: name, note: note);
  }

  @override
  void stageArchiveCondition(String conditionId) {
    stageArchiveConditionCallCount++;
    lastStageArchiveConditionId = conditionId;
    super.stageArchiveCondition(conditionId);
  }
}

/// Never completes so [visitDocumentationProvider] stays in loading.
class LoadingVisitDocumentationNotifier extends VisitDocumentationNotifier {
  LoadingVisitDocumentationNotifier(super.visitId);

  @override
  Future<VisitDocumentationState> build() async {
    return Completer<VisitDocumentationState>().future;
  }
}

/// Throws on build to surface the documentation error state.
class ErrorVisitDocumentationNotifier extends VisitDocumentationNotifier {
  ErrorVisitDocumentationNotifier(super.visitId, this._error);

  final Object _error;

  @override
  Future<VisitDocumentationState> build() async => throw _error;
}

class StubPatientSafetyNotifier extends PatientSafetyNotifier {
  StubPatientSafetyNotifier(super.patientId, this._context);

  final PatientSafetyContext _context;

  @override
  Future<PatientSafetyContext> build() async => _context;
}

class LoadingPatientSafetyNotifier extends PatientSafetyNotifier {
  LoadingPatientSafetyNotifier(super.patientId);

  @override
  Future<PatientSafetyContext> build() async {
    return Completer<PatientSafetyContext>().future;
  }
}

class ErrorPatientSafetyNotifier extends PatientSafetyNotifier {
  ErrorPatientSafetyNotifier(super.patientId, this._error);

  final Object _error;

  @override
  Future<PatientSafetyContext> build() async => throw _error;
}

/// Records [EncounterActivePhaseNotifier.setPhase] calls.
class SpyEncounterActivePhaseNotifier extends EncounterActivePhaseNotifier {
  SpyEncounterActivePhaseNotifier(super.visitId);

  var setPhaseCallCount = 0;
  EncounterPhase? lastPhase;

  @override
  void setPhase(EncounterPhase phase) {
    setPhaseCallCount++;
    lastPhase = phase;
    super.setPhase(phase);
  }
}

AuthSessionState visitsAuthSession({
  Set<String>? permissions,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final branches = branchIds ?? [encounterTestBranchId];
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: permissions ?? RolePermissionSeed.administrator,
      branchIds: branches,
      activeBranchId: activeBranchId ?? branches.first,
    ),
  );
}

VisitDetailViewState buildVisitDetailView({
  VisitDetail? visit,
  bool? canEditDocumentation,
  bool? hasBranchAccess,
  bool? canUploadAttachments,
}) {
  final resolved = visit ?? sampleEncounterVisit();
  return VisitDetailViewState(
    visit: resolved,
    canEditDocumentation: canEditDocumentation ?? true,
    hasBranchAccess: hasBranchAccess ?? true,
    canUploadAttachments: canUploadAttachments ?? true,
  );
}

List<Override> visitsProviderOverrides({
  AuthSessionState? auth,
  VisitRpcTestClient? rpcClient,
  String? visitId,
  VisitDocumentationState? docState,
  Object? docError,
  bool docLoading = false,
  StubVisitDocumentationNotifier? docNotifier,
  VisitDetailViewState? detailView,
  Object? detailError,
  String? patientId,
  PatientSafetyContext? patientSafety,
  Object? patientSafetyError,
  bool patientSafetyLoading = false,
  SpyEncounterActivePhaseNotifier? activePhaseNotifier,
  List<Override> extraOverrides = const [],
}) {
  final client = rpcClient ?? VisitRpcTestClient();
  final resolvedAuth = auth ?? visitsAuthSession();
  final visitRepo = VisitRepository(client);

  return [
    authSessionProvider.overrideWith(
      () => MutableAuthSessionNotifier(resolvedAuth),
    ),
    permissionServiceProvider.overrideWith(
      (ref) => PermissionService(ref.watch(authSessionProvider).context),
    ),
    visitRepositoryProvider.overrideWith((ref) => visitRepo),
    visitAttachmentServiceProvider.overrideWith(
      (ref) => VisitAttachmentService(client, visitRepo),
    ),
    if (visitId != null)
      if (docNotifier != null)
        visitDocumentationProvider(visitId).overrideWith(() => docNotifier)
      else if (docError != null)
        visitDocumentationProvider(visitId).overrideWith(
          () => ErrorVisitDocumentationNotifier(visitId, docError),
        )
      else if (docLoading)
        visitDocumentationProvider(visitId).overrideWith(
          () => LoadingVisitDocumentationNotifier(visitId),
        )
      else if (docState != null)
        visitDocumentationProvider(visitId).overrideWith(
          () => StubVisitDocumentationNotifier(visitId, docState),
        ),
    if (visitId != null)
      if (detailError != null)
        visitDetailViewProvider(visitId).overrideWith(
          (ref) async => throw detailError,
        )
      else
        visitDetailViewProvider(visitId).overrideWith(
          (ref) async => detailView ?? buildVisitDetailView(),
        ),
    if (patientId != null)
      if (patientSafetyLoading)
        patientSafetyProvider(patientId).overrideWith(
          () => LoadingPatientSafetyNotifier(patientId),
        )
      else if (patientSafetyError != null)
        patientSafetyProvider(patientId).overrideWith(
          () => ErrorPatientSafetyNotifier(patientId, patientSafetyError),
        )
      else if (patientSafety != null)
        patientSafetyProvider(patientId).overrideWith(
          () => StubPatientSafetyNotifier(patientId, patientSafety),
        ),
    if (visitId != null && activePhaseNotifier != null)
      encounterActivePhaseProvider(visitId).overrideWith(() => activePhaseNotifier),
    ...extraOverrides,
  ];
}

/// GoRouter with stub destination markers for visit navigation assertions.
GoRouter createVisitsTestRouter({
  required Widget home,
  String? initialLocation,
  List<RouteBase> extraRoutes = const [],
}) {
  Widget marker(String label) => Scaffold(
        key: Key('route_$label'),
        body: Center(child: Text('stub:$label')),
      );

  return GoRouter(
    initialLocation: initialLocation ?? AppRoutes.visitDocument(encounterTestVisitId),
    routes: [
      GoRoute(
        path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
        builder: (_, _) => home,
      ),
      GoRoute(
        path: AppRoutes.appointmentsCalendar,
        builder: (_, _) => marker('appointments-calendar'),
      ),
      GoRoute(
        path: '${AppRoutes.appointments}/:appointmentId',
        builder: (context, state) => marker(
          'appointment-${state.pathParameters['appointmentId']}',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.patients}/:patientId',
        builder: (context, state) => marker(
          'patient-${state.pathParameters['patientId']}',
        ),
      ),
      GoRoute(
        path: '${AppRoutes.billing}/${AppRoutes.billingVisitSegment}/:visitId',
        builder: (context, state) => marker(
          'visit-billing-${state.pathParameters['visitId']}',
        ),
      ),
      ...extraRoutes,
    ],
  );
}

/// Pumps [child] inside the canonical visits widget-test shell.
Future<void> pumpVisitsSurface(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
  Size surfaceSize = visitsWideSurfaceSize,
  bool wrapToastHost = true,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final appChild = wrapToastHost
      ? AppToastHost(
          child: Scaffold(
            body: SizedBox(
              width: surfaceSize.width,
              height: surfaceSize.height,
              child: child,
            ),
          ),
        )
      : Scaffold(
          body: SizedBox(
            width: surfaceSize.width,
            height: surfaceSize.height,
            child: child,
          ),
        );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: appChild,
      ),
    ),
  );
}

/// Pumps [home] behind a visits [GoRouter] with stub route markers.
Future<GoRouter> pumpVisitsRouter(
  WidgetTester tester, {
  required Widget home,
  String? initialLocation,
  List<Override> overrides = const [],
  Size surfaceSize = visitsWideSurfaceSize,
  List<RouteBase> extraRoutes = const [],
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final router = createVisitsTestRouter(
    home: home,
    initialLocation: initialLocation,
    extraRoutes: extraRoutes,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );

  return router;
}

ProviderContainer visitsProviderContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> pumpVisitsFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Deterministic attachment pick input for [StubVisitDocumentationNotifier] tests.
VisitAttachmentPickInput buildVisitAttachmentPickInput({
  String filename = 'lab-result.pdf',
  Uint8List? bytes,
}) {
  return VisitAttachmentPickInput(
    filename: filename,
    bytes: bytes ?? Uint8List.fromList(const [1, 2, 3, 4]),
  );
}
