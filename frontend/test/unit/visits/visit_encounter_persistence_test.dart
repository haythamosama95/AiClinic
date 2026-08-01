import 'dart:typed_data';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/application/visit_encounter_persistence.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

const _vitalSignId = 'ssssssss-ssss-4sss-8sss-ssssssssssss';
const _investigationLineId = 'nnnnnnnn-nnnn-4nnn-8nnn-nnnnnnnnnnnn';
const _treatmentPlanId = 'tttttttt-tttt-4ttt-8ttt-tttttttttttt';
const _attachmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _allergyId = 'allergy-1';
const _medicationRecordId = 'medication-1';
const _conditionId = 'condition-1';
const _organizationId = '00000000-0000-4000-8000-000000000020';

Map<String, Map<String, dynamic>> _successRpcResults() => {
  'create_visit_vital_sign': {
    'success': true,
    'data': {'vital_sign_id': _vitalSignId},
  },
  'update_visit_vital_sign': {'success': true, 'data': {}},
  'archive_visit_vital_sign': {'success': true, 'data': {}},
  'create_visit_investigation': {
    'success': true,
    'data': {'investigation_line_id': _investigationLineId},
  },
  'update_visit_investigation': {'success': true, 'data': {}},
  'archive_visit_investigation': {'success': true, 'data': {}},
  'record_investigation_result': {
    'success': true,
    'data': {'result_recorded_at': '2026-05-31T11:00:00.000Z'},
  },
  'create_treatment_plan': {
    'success': true,
    'data': {'treatment_plan_id': _treatmentPlanId},
  },
  'update_treatment_plan': {'success': true, 'data': {}},
  'archive_treatment_plan': {'success': true, 'data': {}},
  'delete_visit_attachment': {'success': true, 'data': {'attachment_id': _attachmentId}},
  'create_patient_allergy': {'success': true, 'data': {'id': _allergyId}},
  'update_patient_allergy': {'success': true, 'data': {}},
  'archive_patient_allergy': {'success': true, 'data': {}},
  'create_patient_medication': {'success': true, 'data': {'id': _medicationRecordId}},
  'update_patient_medication': {'success': true, 'data': {}},
  'archive_patient_medication': {'success': true, 'data': {}},
  'create_patient_chronic_condition': {'success': true, 'data': {'id': _conditionId}},
  'update_patient_chronic_condition': {'success': true, 'data': {}},
  'archive_patient_chronic_condition': {'success': true, 'data': {}},
};

VisitAttachmentPickInput _samplePick() => VisitAttachmentPickInput(
  filename: 'lab.pdf',
  bytes: Uint8List.fromList([1, 2, 3]),
);

class _StaticPatientSafetyNotifier extends PatientSafetyNotifier {
  _StaticPatientSafetyNotifier(this._context) : super(encounterTestPatientId);

  final PatientSafetyContext _context;

  @override
  Future<PatientSafetyContext> build() async => _context;
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _SeededVisitDocumentationNotifier extends VisitDocumentationNotifier {
  _SeededVisitDocumentationNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;

  @override
  Future<VisitDocumentationState> build() async => _state;
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _RecordingVisitAttachmentService extends VisitAttachmentService {
  _RecordingVisitAttachmentService(VisitRepository repository) : super(_FakeSupabaseClient(), repository);

  int uploadCalls = 0;
  String? lastVisitId;
  String? lastLabel;

  @override
  Future<String> uploadAndRegister({
    required String organizationId,
    required String branchId,
    required String visitId,
    required VisitAttachmentPickInput pick,
    String? label,
  }) async {
    uploadCalls += 1;
    lastVisitId = visitId;
    lastLabel = label;
    return _attachmentId;
  }
}

Future<({WidgetRef ref, ProviderContainer container, VisitRpcTestClient client})> _pumpHarness(
  WidgetTester tester, {
  required bool deferPersistence,
  VisitDocumentationState? seedState,
  Map<String, Map<String, dynamic>>? rpcResults,
  VisitAttachmentService? attachmentService,
}) async {
  final client = VisitRpcTestClient(rpcResults: rpcResults ?? _successRpcResults());
  late WidgetRef widgetRef;
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
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
          () => _SeededVisitDocumentationNotifier(seedState ?? sampleEncounterDocState()),
        ),
        if (attachmentService != null) visitAttachmentServiceProvider.overrideWithValue(attachmentService),
      ],
      child: Consumer(
        builder: (context, ref, child) {
          widgetRef = ref;
          ref.watch(visitDocumentationProvider(encounterTestVisitId));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  container = ProviderScope.containerOf(tester.element(find.byType(Consumer)));
  addTearDown(container.dispose);
  await container.read(visitDocumentationProvider(encounterTestVisitId).future);

  return (ref: widgetRef, container: container, client: client);
}

VisitEncounterPersistence _persistence(WidgetRef ref, {required bool deferPersistence}) {
  return visitEncounterPersistence(ref, visitId: encounterTestVisitId, deferPersistence: deferPersistence);
}

void main() {
  group('visitEncounterPersistence factory', () {
    testWidgets('trivial: factory returns VisitEncounterPersistence with supplied flags', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);

      final persistence = visitEncounterPersistence(
        harness.ref,
        visitId: encounterTestVisitId,
        deferPersistence: true,
      );

      expect(persistence, isA<VisitEncounterPersistence>());
      await persistence.createVisitVitalSign(name: 'BP', value: '120/80');
      expect(harness.client.rpcLog, isEmpty);
    });
  });

  group('VisitEncounterPersistence deferPersistence: true', () {
    testWidgets('trivial: vital sign mutations stage into draft without RPC', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);

      await persistence.createVisitVitalSign(name: 'BP', value: '120/80', unit: 'mmHg');
      await persistence.archiveVisitVitalSign(vitalSignId: _vitalSignId);

      expect(harness.client.rpcLog, isEmpty);
      final draft = harness.container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.encounterDraft;
      expect(draft.pendingVitalSigns, hasLength(1));
      expect(draft.pendingVitalSigns.first.name, 'BP');
      expect(draft.archivedVitalSignIds, contains(_vitalSignId));
    });

    testWidgets('trivial: investigation mutations stage into draft without RPC', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);

      await persistence.createVisitInvestigation(name: 'CBC', note: 'Routine');
      await persistence.recordInvestigationResult(investigationLineId: _investigationLineId, result: 'Normal');
      await persistence.archiveVisitInvestigation(investigationLineId: _investigationLineId);

      expect(harness.client.rpcLog, isEmpty);
      final draft = harness.container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.encounterDraft;
      expect(draft.pendingInvestigations, hasLength(1));
      expect(draft.archivedInvestigationIds, contains(_investigationLineId));
    });

    testWidgets('trivial: treatment plan mutations stage into draft without RPC', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);

      await persistence.createTreatmentPlan(
        medicationName: 'Ibuprofen',
        dosage: '400mg',
        frequency: 'daily',
        duration: '5 days',
      );
      await persistence.archiveTreatmentPlan(treatmentPlanId: _treatmentPlanId);

      expect(harness.client.rpcLog, isEmpty);
      final draft = harness.container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.encounterDraft;
      expect(draft.pendingTreatmentPlans, hasLength(1));
      expect(draft.archivedTreatmentPlanIds, contains(_treatmentPlanId));
    });

    testWidgets('trivial: attachment and patient safety mutations stage without RPC', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);

      await persistence.stageAttachment(
        pick: _samplePick(),
        label: 'Lab PDF',
        uploadedBy: 'staff-1',
        uploadedByName: 'Dr Test',
      );
      await persistence.deleteVisitAttachment(attachmentId: _attachmentId);
      await persistence.createPatientAllergy(
        patientId: encounterTestPatientId,
        substance: 'Penicillin',
        reaction: 'Rash',
      );
      await persistence.updatePatientAllergy(allergyId: _allergyId, substance: 'Penicillin V');
      await persistence.archivePatientAllergy(allergyId: _allergyId);
      await persistence.createPatientMedication(
        patientId: encounterTestPatientId,
        name: 'Metformin',
      );
      await persistence.updatePatientMedication(medicationRecordId: _medicationRecordId, note: 'Daily');
      await persistence.archivePatientMedication(medicationRecordId: _medicationRecordId);
      await persistence.createPatientChronicCondition(
        patientId: encounterTestPatientId,
        name: 'Hypertension',
      );
      await persistence.updatePatientChronicCondition(conditionId: _conditionId, note: 'Controlled');
      await persistence.archivePatientChronicCondition(conditionId: _conditionId);

      expect(harness.client.rpcLog, isEmpty);
      final draft = harness.container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.encounterDraft;
      expect(draft.pendingAttachments, hasLength(1));
      expect(draft.deletedAttachmentIds, contains(_attachmentId));
      expect(draft.patientSafety.pendingAllergies, hasLength(1));
      expect(draft.patientSafety.archivedAllergyIds, contains(_allergyId));
      expect(draft.patientSafety.pendingMedications, hasLength(1));
      expect(draft.patientSafety.pendingConditions, hasLength(1));
    });

    testWidgets('invalid state: uploadAndRegisterAttachment throws when deferring', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);

      await expectLater(
        () => persistence.uploadAndRegisterAttachment(
          organizationId: _organizationId,
          branchId: encounterTestBranchId,
          pick: _samplePick(),
          label: 'Lab',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'uploadAndRegisterAttachment is not used when deferPersistence is true.',
          ),
        ),
      );
    });
  });

  group('VisitEncounterPersistence deferPersistence: false', () {
    testWidgets('advanced: each clinical mutation invokes the matching RPC with params', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: false);
      final persistence = _persistence(harness.ref, deferPersistence: false);

      await persistence.createVisitVitalSign(
        name: 'BP',
        value: '120/80',
        unit: 'mmHg',
        predefinedVitalSignId: 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv',
      );
      await persistence.updateVisitVitalSign(vitalSignId: _vitalSignId, value: '118/76');
      await persistence.archiveVisitVitalSign(vitalSignId: _vitalSignId);
      await persistence.createVisitInvestigation(name: 'CBC', note: 'Routine', investigationId: 'inv-1');
      await persistence.updateVisitInvestigation(
        investigationLineId: _investigationLineId,
        name: 'CBC updated',
        updateInvestigationId: true,
        investigationId: 'inv-2',
      );
      await persistence.archiveVisitInvestigation(investigationLineId: _investigationLineId);
      await persistence.recordInvestigationResult(investigationLineId: _investigationLineId, result: 'Normal');
      await persistence.createTreatmentPlan(
        medicationName: 'Ibuprofen',
        dosage: '400mg',
        frequency: 'daily',
        duration: '5 days',
      );
      await persistence.updateTreatmentPlan(treatmentPlanId: _treatmentPlanId, notes: 'With food');
      await persistence.archiveTreatmentPlan(treatmentPlanId: _treatmentPlanId);
      await persistence.deleteVisitAttachment(attachmentId: _attachmentId);
      await persistence.createPatientAllergy(
        patientId: encounterTestPatientId,
        substance: 'Penicillin',
        reaction: 'Rash',
      );
      await persistence.updatePatientAllergy(allergyId: _allergyId, substance: 'Penicillin V');
      await persistence.archivePatientAllergy(allergyId: _allergyId);
      await persistence.createPatientMedication(
        patientId: encounterTestPatientId,
        name: 'Metformin',
        medicationId: 'med-1',
        note: 'Daily',
      );
      await persistence.updatePatientMedication(medicationRecordId: _medicationRecordId, note: 'Nightly');
      await persistence.archivePatientMedication(medicationRecordId: _medicationRecordId);
      await persistence.createPatientChronicCondition(
        patientId: encounterTestPatientId,
        name: 'Hypertension',
        note: 'Controlled',
      );
      await persistence.updatePatientChronicCondition(conditionId: _conditionId, note: 'Stable');
      await persistence.archivePatientChronicCondition(conditionId: _conditionId);

      const expectedRpcs = [
        'create_visit_vital_sign',
        'update_visit_vital_sign',
        'archive_visit_vital_sign',
        'create_visit_investigation',
        'update_visit_investigation',
        'archive_visit_investigation',
        'record_investigation_result',
        'create_treatment_plan',
        'update_treatment_plan',
        'archive_treatment_plan',
        'delete_visit_attachment',
        'create_patient_allergy',
        'update_patient_allergy',
        'archive_patient_allergy',
        'create_patient_medication',
        'update_patient_medication',
        'archive_patient_medication',
        'create_patient_chronic_condition',
        'update_patient_chronic_condition',
        'archive_patient_chronic_condition',
      ];
      expect(harness.client.rpcLog, expectedRpcs);

      expect(harness.client.paramsForFunction('create_visit_vital_sign')?['p_visit_id'], encounterTestVisitId);
      expect(harness.client.paramsForFunction('create_visit_vital_sign')?['p_name'], 'BP');
      expect(harness.client.paramsForFunction('create_treatment_plan')?['p_dosage'], '400mg');
      expect(harness.client.paramsForFunction('create_patient_allergy')?['p_patient_id'], encounterTestPatientId);

      final draft = harness.container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.encounterDraft;
      expect(draft.isEmpty, isTrue);
    });

    testWidgets('advanced: uploadAndRegisterAttachment delegates to attachment service', (tester) async {
      final repository = VisitRepository(VisitRpcTestClient(rpcResults: _successRpcResults()));
      final attachmentService = _RecordingVisitAttachmentService(repository);
      final harness = await _pumpHarness(
        tester,
        deferPersistence: false,
        attachmentService: attachmentService,
      );
      final persistence = _persistence(harness.ref, deferPersistence: false);

      await persistence.uploadAndRegisterAttachment(
        organizationId: _organizationId,
        branchId: encounterTestBranchId,
        pick: _samplePick(),
        label: 'Lab PDF',
      );

      expect(attachmentService.uploadCalls, 1);
      expect(attachmentService.lastVisitId, encounterTestVisitId);
      expect(attachmentService.lastLabel, 'Lab PDF');
    });

    testWidgets('invalid state: stageAttachment throws without deferPersistence', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: false);
      final persistence = _persistence(harness.ref, deferPersistence: false);

      await expectLater(
        () => persistence.stageAttachment(
          pick: _samplePick(),
          label: 'Lab',
          uploadedBy: 'staff-1',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'stageAttachment requires deferPersistence.',
          ),
        ),
      );
    });

    testWidgets('invalid state: RPC failure propagates from immediate mutations', (tester) async {
      final results = _successRpcResults();
      results['create_visit_vital_sign'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Rejected',
      };
      final harness = await _pumpHarness(tester, deferPersistence: false, rpcResults: results);
      final persistence = _persistence(harness.ref, deferPersistence: false);

      await expectLater(
        () => persistence.createVisitVitalSign(name: 'BP', value: '120/80'),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_ERROR')),
      );
    });
  });

  group('VisitEncounterPersistence.effectivePatientSafety', () {
    testWidgets('trivial: immediate mode returns base context unchanged', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: false);
      final persistence = _persistence(harness.ref, deferPersistence: false);
      const base = PatientSafetyContext(
        allergies: [PatientAllergy(id: 'a-1', substance: 'Latex')],
      );

      expect(persistence.effectivePatientSafety(base), base);
    });

    testWidgets('advanced: deferred mode merges staged patient safety draft', (tester) async {
      final harness = await _pumpHarness(tester, deferPersistence: true);
      final persistence = _persistence(harness.ref, deferPersistence: true);
      const base = PatientSafetyContext();

      await persistence.createPatientAllergy(
        patientId: encounterTestPatientId,
        substance: 'Penicillin',
      );

      final effective = persistence.effectivePatientSafety(base);

      expect(effective.allergies, hasLength(1));
      expect(effective.allergies.first.substance, 'Penicillin');
    });
  });
}
