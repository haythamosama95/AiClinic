import 'dart:typed_data';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  late VisitRpcTestClient client;

  ProviderContainer createContainer(VisitDocumentationState seedState) {
    return ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(
          () => _PresetAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(
                branchIds: [encounterTestBranchId],
                activeBranchId: encounterTestBranchId,
                permissions: {PermissionKeys.visitsEditSoap, PermissionKeys.visitsCreate},
              ),
            ),
          ),
        ),
        visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
        patientSafetyProvider(encounterTestPatientId).overrideWith(
          () => _StaticPatientSafetyNotifier(buildPatientSafetyContext()),
        ),
        visitDocumentationProvider(encounterTestVisitId).overrideWith(
          () => _SeededVisitDocumentationNotifier(seedState),
        ),
      ],
    );
  }

  Future<VisitDocumentationNotifier> loadNotifier(ProviderContainer container) async {
    await container.read(visitDocumentationProvider(encounterTestVisitId).future);
    return container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
  }

  VisitDocumentationState readState(ProviderContainer container) {
    return container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
  }

  setUp(() {
    client = VisitRpcTestClient();
  });

  group('VisitDocumentationNotifier staging — vital signs', () {
    test('trivial: stageCreateVitalSign appends pending sign without RPC', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38.5', unit: 'C');

      final draft = readState(container).encounterDraft;
      expect(draft.pendingVitalSigns, hasLength(1));
      expect(draft.pendingVitalSigns.first.name, 'Temp');
      expect(isVisitDraftId(draft.pendingVitalSigns.first.id), isTrue);
      expect(client.rpcLog, isEmpty);
    });

    test('advanced: create-then-update targets staged draft id', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38.0');
      final draftId = readState(container).encounterDraft.pendingVitalSigns.single.id;

      notifier.stageUpdateVitalSign(vitalSignId: draftId, value: '39.0');

      final pending = readState(container).encounterDraft.pendingVitalSigns;
      expect(pending, hasLength(1));
      expect(pending.single.id, draftId);
      expect(pending.single.value, '39.0');
      expect(readState(container).encounterDraft.vitalSignUpdates, isEmpty);
    });

    test('advanced: create-then-archive removes pending create without archive RPC id', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38.0');
      final draftId = readState(container).encounterDraft.pendingVitalSigns.single.id;

      notifier.stageArchiveVitalSign(draftId);

      final draft = readState(container).encounterDraft;
      expect(draft.pendingVitalSigns, isEmpty);
      expect(draft.archivedVitalSignIds, isEmpty);
    });

    test('advanced: update persisted row stages vitalSignUpdates map', () async {
      final visit = sampleEncounterVisit(vitalSigns: [buildVisitVitalSign(value: '120/80')]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageUpdateVitalSign(vitalSignId: encounterTestVitalSignId, value: '130/85');

      final draft = readState(container).encounterDraft;
      expect(draft.pendingVitalSigns, isEmpty);
      expect(draft.vitalSignUpdates[encounterTestVitalSignId]?.value, '130/85');
      expect(readState(container).visit.vitalSigns.single.value, '130/85');
    });

    test('advanced: update-then-archive persisted row moves id to archivedVitalSignIds', () async {
      final visit = sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageUpdateVitalSign(vitalSignId: encounterTestVitalSignId, value: '130/85');
      notifier.stageArchiveVitalSign(encounterTestVitalSignId);

      final draft = readState(container).encounterDraft;
      expect(draft.archivedVitalSignIds, {encounterTestVitalSignId});
      expect(draft.vitalSignUpdates, isEmpty);
      expect(readState(container).visit.vitalSigns, isEmpty);
    });

    test('invalid state: update unknown id is a no-op', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageUpdateVitalSign(vitalSignId: 'unknown-id', value: 'x');

      expect(readState(container).encounterDraft.isEmpty, isTrue);
    });

    test('edge case: archive-then-update on persisted id cannot find removed row', () async {
      final visit = sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageArchiveVitalSign(encounterTestVitalSignId);
      notifier.stageUpdateVitalSign(vitalSignId: encounterTestVitalSignId, value: '999');

      expect(readState(container).encounterDraft.vitalSignUpdates, isEmpty);
    });

    test('edge case: duplicate archive of persisted id is idempotent', () async {
      final visit = sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageArchiveVitalSign(encounterTestVitalSignId);
      notifier.stageArchiveVitalSign(encounterTestVitalSignId);

      expect(readState(container).encounterDraft.archivedVitalSignIds, {encounterTestVitalSignId});
    });
  });

  group('VisitDocumentationNotifier staging — investigations', () {
    test('trivial: stageCreateInvestigation appends pending investigation', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateInvestigation(name: 'CBC', note: 'Fasting');

      final pending = readState(container).encounterDraft.pendingInvestigations;
      expect(pending, hasLength(1));
      expect(pending.single.name, 'CBC');
      expect(client.rpcLog, isEmpty);
    });

    test('advanced: create-then-update keeps single pending row', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateInvestigation(name: 'CBC');
      final draftId = readState(container).encounterDraft.pendingInvestigations.single.id;
      notifier.stageUpdateInvestigation(investigationLineId: draftId, name: 'CMP');

      final pending = readState(container).encounterDraft.pendingInvestigations;
      expect(pending, hasLength(1));
      expect(pending.single.id, draftId);
      expect(pending.single.name, 'CMP');
    });

    test('advanced: create-then-archive clears pending and staged results', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateInvestigation(name: 'CBC');
      final draftId = readState(container).encounterDraft.pendingInvestigations.single.id;
      notifier.stageInvestigationResult(investigationLineId: draftId, result: 'Normal');
      notifier.stageArchiveInvestigation(draftId);

      final draft = readState(container).encounterDraft;
      expect(draft.pendingInvestigations, isEmpty);
      expect(draft.investigationResults, isEmpty);
    });

    test('advanced: stageInvestigationResult trims whitespace', () async {
      final visit = sampleEncounterVisit(investigations: [buildVisitInvestigation()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageInvestigationResult(investigationLineId: encounterTestInvestigationLineId, result: '  Positive  ');

      expect(
        readState(container).encounterDraft.investigationResults[encounterTestInvestigationLineId],
        'Positive',
      );
    });

    test('advanced: archive persisted investigation clears staged result', () async {
      final visit = sampleEncounterVisit(investigations: [buildVisitInvestigation()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageInvestigationResult(investigationLineId: encounterTestInvestigationLineId, result: 'High');
      notifier.stageArchiveInvestigation(encounterTestInvestigationLineId);

      final draft = readState(container).encounterDraft;
      expect(draft.archivedInvestigationIds, {encounterTestInvestigationLineId});
      expect(draft.investigationResults, isEmpty);
    });
  });

  group('VisitDocumentationNotifier staging — treatment plans', () {
    test('trivial: stageCreateTreatmentPlan appends pending plan', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateTreatmentPlan(medicationName: 'Ibuprofen', dosage: '400mg');

      final pending = readState(container).encounterDraft.pendingTreatmentPlans;
      expect(pending, hasLength(1));
      expect(pending.single.medicationName, 'Ibuprofen');
      expect(client.rpcLog, isEmpty);
    });

    test('advanced: create-then-update on draft id is last-write-wins', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateTreatmentPlan(medicationName: 'Drug A');
      final draftId = readState(container).encounterDraft.pendingTreatmentPlans.single.id;
      notifier.stageUpdateTreatmentPlan(treatmentPlanId: draftId, medicationName: 'Drug B', dosage: '10mg');

      final plan = readState(container).encounterDraft.pendingTreatmentPlans.single;
      expect(plan.id, draftId);
      expect(plan.medicationName, 'Drug B');
      expect(plan.dosage, '10mg');
    });

    test('advanced: create-then-archive removes pending plan', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateTreatmentPlan(medicationName: 'Drug A');
      final draftId = readState(container).encounterDraft.pendingTreatmentPlans.single.id;
      notifier.stageArchiveTreatmentPlan(draftId);

      expect(readState(container).encounterDraft.pendingTreatmentPlans, isEmpty);
    });

    test('advanced: update persisted plan stages treatmentPlanUpdates', () async {
      final visit = sampleEncounterVisit(treatmentPlans: [buildVisitTreatmentPlanItem()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageUpdateTreatmentPlan(treatmentPlanId: encounterTestTreatmentPlanId, dosage: '500mg');

      expect(
        readState(container).encounterDraft.treatmentPlanUpdates[encounterTestTreatmentPlanId]?.dosage,
        '500mg',
      );
    });
  });

  group('VisitDocumentationNotifier staging — attachments', () {
    test('trivial: stageAttachment appends pending attachment for valid file type', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageAttachment(
        pick: VisitAttachmentPickInput(filename: 'lab.pdf', bytes: Uint8List.fromList([1, 2, 3])),
        label: 'Lab',
        uploadedBy: encounterTestDoctorId,
      );

      final pending = readState(container).encounterDraft.pendingAttachments;
      expect(pending, hasLength(1));
      expect(pending.single.label, 'Lab');
      expect(client.rpcLog, isEmpty);
    });

    test('invalid state: unsupported file extension is a no-op', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageAttachment(
        pick: VisitAttachmentPickInput(filename: 'notes.txt', bytes: Uint8List.fromList([1])),
        label: 'Notes',
        uploadedBy: encounterTestDoctorId,
      );

      expect(readState(container).encounterDraft.pendingAttachments, isEmpty);
    });

    test('advanced: stageDeleteAttachment removes pending draft attachment', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageAttachment(
        pick: VisitAttachmentPickInput(filename: 'lab.pdf', bytes: Uint8List.fromList([1])),
        label: 'Lab',
        uploadedBy: encounterTestDoctorId,
      );
      final draftId = readState(container).encounterDraft.pendingAttachments.single.id;
      notifier.stageDeleteAttachment(draftId);

      expect(readState(container).encounterDraft.pendingAttachments, isEmpty);
    });

    test('advanced: stageDeleteAttachment on persisted id stages deletedAttachmentIds', () async {
      final visit = sampleEncounterVisit(attachments: [buildVisitAttachmentItem()]);
      final container = createContainer(sampleEncounterDocState(visit: visit, persistedVisit: visit));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageDeleteAttachment(encounterTestAttachmentId);

      final draft = readState(container).encounterDraft;
      expect(draft.deletedAttachmentIds, {encounterTestAttachmentId});
      expect(readState(container).visit.attachments, isEmpty);
    });
  });

  group('VisitDocumentationNotifier staging — patient safety', () {
    test('trivial: stageCreateAllergy appends pending allergy', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateAllergy(substance: 'Penicillin', reaction: 'Rash');

      final pending = readState(container).encounterDraft.patientSafety.pendingAllergies;
      expect(pending, hasLength(1));
      expect(pending.single.substance, 'Penicillin');
      expect(client.rpcLog, isEmpty);
    });

    test('advanced: update persisted allergy from patient safety context', () async {
      final safety = buildPatientSafetyContext(allergies: [buildPatientAllergy(substance: 'Peanuts')]);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  branchIds: [encounterTestBranchId],
                  permissions: {PermissionKeys.visitsEditSoap},
                ),
              ),
            ),
          ),
          visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
          patientSafetyProvider(encounterTestPatientId).overrideWith(() => _StaticPatientSafetyNotifier(safety)),
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _SeededVisitDocumentationNotifier(sampleEncounterDocState()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);
      await container.read(patientSafetyProvider(encounterTestPatientId).future);

      notifier.stageUpdateAllergy(allergyId: encounterTestAllergyId, reaction: 'Anaphylaxis');

      final updates = readState(container).encounterDraft.patientSafety.allergyUpdates;
      expect(updates[encounterTestAllergyId]?.reaction, 'Anaphylaxis');
    });

    test('advanced: create-then-archive allergy removes pending row', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateAllergy(substance: 'Latex');
      final draftId = readState(container).encounterDraft.patientSafety.pendingAllergies.single.id;
      notifier.stageArchiveAllergy(draftId);

      expect(readState(container).encounterDraft.patientSafety.pendingAllergies, isEmpty);
    });

    test('advanced: stageCreateMedication and stageUpdateMedication on draft id', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateMedication(name: 'Metformin');
      final draftId = readState(container).encounterDraft.patientSafety.pendingMedications.single.id;
      notifier.stageUpdateMedication(medicationRecordId: draftId, note: '500mg daily');

      final med = readState(container).encounterDraft.patientSafety.pendingMedications.single;
      expect(med.id, draftId);
      expect(med.note, '500mg daily');
    });

    test('advanced: stageCreateCondition and archive persisted condition', () async {
      final safety = buildPatientSafetyContext(
        chronicConditions: [buildPatientChronicCondition(name: 'Asthma')],
      );
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  branchIds: [encounterTestBranchId],
                  permissions: {PermissionKeys.visitsEditSoap},
                ),
              ),
            ),
          ),
          visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
          patientSafetyProvider(encounterTestPatientId).overrideWith(() => _StaticPatientSafetyNotifier(safety)),
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _SeededVisitDocumentationNotifier(sampleEncounterDocState()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateCondition(name: 'Hypertension');
      expect(readState(container).encounterDraft.patientSafety.pendingConditions, hasLength(1));

      notifier.stageArchiveCondition(encounterTestConditionId);
      expect(
        readState(container).encounterDraft.patientSafety.archivedConditionIds,
        {encounterTestConditionId},
      );
    });

    test('invalid state: update unknown persisted allergy without substance is a no-op', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageUpdateAllergy(allergyId: 'missing-id', reaction: 'Rash');

      expect(readState(container).encounterDraft.patientSafety.allergyUpdates, isEmpty);
    });
  });

  group('VisitDocumentationNotifier staging — mutation guards', () {
    test('invalid state: completed visit in viewing mode blocks staging', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit);
      final container = createContainer(state);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38');

      expect(readState(container).encounterDraft.isEmpty, isTrue);
    });

    test('advanced: completed visit in workspace editing mode allows staging', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit).copyWith(
        workspaceEditMode: WorkspaceEditMode.editing,
      );
      final container = createContainer(state);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38');

      expect(readState(container).encounterDraft.pendingVitalSigns, hasLength(1));
    });

    test('edge case: staging sets saveStatus idle and clears prior error', () async {
      final container = createContainer(
        sampleEncounterDocState(saveStatus: DocumentationSaveStatus.error, errorMessage: 'Old'),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.stageCreateVitalSign(name: 'Temp', value: '38');

      final next = readState(container);
      expect(next.saveStatus, DocumentationSaveStatus.idle);
      expect(next.errorMessage, isNull);
    });
  });
}

class _SeededVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SeededVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _StaticPatientSafetyNotifier extends PatientSafetyNotifier {
  _StaticPatientSafetyNotifier(this._context) : super(encounterTestPatientId);

  final PatientSafetyContext _context;

  @override
  Future<PatientSafetyContext> build() async => _context;
}
