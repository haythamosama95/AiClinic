import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';
import 'visit_encounter_test_support.dart';

List<Override> _deferredPersistenceOverrides({
  required _DeferredPersistenceRpcClient client,
  required VisitDocumentationState seedState,
}) {
  return [
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
    visitAttachmentServiceProvider.overrideWith(
      (ref) => VisitAttachmentService(_NoOpAttachmentStorageTestClient(), VisitRepository(client)),
    ),
    visitDocumentationProvider(
      encounterTestVisitId,
    ).overrideWith(() => _SeededVisitDocumentationNotifier(seedState)),
  ];
}

void main() {
  group('INT-001 — Deferred vital sign appears after saveAll', () {
    late _DeferredPersistenceRpcClient client;

    ProviderContainer createContainer(VisitDocumentationState seedState) {
      return ProviderContainer(overrides: _deferredPersistenceOverrides(client: client, seedState: seedState));
    }

    setUp(() {
      client = _DeferredPersistenceRpcClient();
    });

    test('stages vital in draft overlay without RPC until saveAll', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      notifier.stageCreateVitalSign(name: 'Heart Rate', value: '72', unit: 'bpm');

      final staged = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(staged.hasPendingEncounterDraft, isTrue);
      expect(staged.hasUnsavedChanges, isTrue);
      expect(staged.persistedVisit.vitalSigns, isEmpty);
      expect(staged.visit.vitalSigns, hasLength(1));
      expect(staged.visit.vitalSigns.single.name, 'Heart Rate');
      expect(staged.visit.vitalSigns.single.value, '72');
      expect(staged.visit.vitalSigns.single.unit, 'bpm');
      expect(isVisitDraftId(staged.visit.vitalSigns.single.id), isTrue);
      expect(staged.encounterDraft.pendingVitalSigns, hasLength(1));
      expect(client.rpcCalls.where((call) => call.fn == 'create_visit_vital_sign'), isEmpty);
    });

    test('saveAll flushes staged vital and reloads persisted visit rows', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      notifier.stageCreateVitalSign(name: 'Heart Rate', value: '72', unit: 'bpm');

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      expect(client.rpcCalls.where((call) => call.fn == 'create_visit_vital_sign'), hasLength(1));
      expect(
        client.paramsForFunction('create_visit_vital_sign'),
        {
          'p_visit_id': encounterTestVisitId,
          'p_name': 'Heart Rate',
          'p_value': '72',
          'p_unit': 'bpm',
        },
      );
      expect(client.rpcCalls.where((call) => call.fn == 'get_visit'), isNotEmpty);

      final after = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(after.encounterDraft.isEmpty, isTrue);
      expect(after.hasPendingEncounterDraft, isFalse);
      expect(after.saveStatus, DocumentationSaveStatus.saved);
      expect(after.persistedVisit.vitalSigns, hasLength(1));
      expect(after.persistedVisit.vitalSigns.single.name, 'Heart Rate');
      expect(after.persistedVisit.vitalSigns.single.value, '72');
      expect(after.persistedVisit.vitalSigns.single.unit, 'bpm');
      expect(isVisitDraftId(after.persistedVisit.vitalSigns.single.id), isFalse);
      expect(after.visit.vitalSigns, after.persistedVisit.vitalSigns);
    });
  });

  group('EDGE-005 — Draft ID collision under rapid create', () {
    late _DeferredPersistenceRpcClient client;

    ProviderContainer createContainer(VisitDocumentationState seedState) {
      return ProviderContainer(overrides: _deferredPersistenceOverrides(client: client, seedState: seedState));
    }

    setUp(() {
      client = _DeferredPersistenceRpcClient();
    });

    test('rapid stageCreateVitalSign assigns unique draft: ids', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      // Same event-loop tick simulates same-microsecond rapid create (QA EDGE-005).
      notifier.stageCreateVitalSign(name: 'Blood Pressure', value: '120/80', unit: 'mmHg');
      notifier.stageCreateVitalSign(name: 'Heart Rate', value: '72', unit: 'bpm');

      final staged = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      final draftIds = staged.encounterDraft.pendingVitalSigns.map((sign) => sign.id).toList();

      expect(draftIds, hasLength(2));
      expect(draftIds.toSet(), hasLength(2));
      for (final id in draftIds) {
        expect(id.startsWith(visitDraftIdPrefix), isTrue);
      }
      expect(staged.visit.vitalSigns, hasLength(2));
      expect(client.rpcCalls.where((call) => call.fn == 'create_visit_vital_sign'), isEmpty);
    });

    test('saveAll persists both rapidly staged vitals on flush', () async {
      final container = createContainer(sampleEncounterDocState());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      notifier.stageCreateVitalSign(name: 'Blood Pressure', value: '120/80', unit: 'mmHg');
      notifier.stageCreateVitalSign(name: 'Heart Rate', value: '72', unit: 'bpm');

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      expect(client.rpcCalls.where((call) => call.fn == 'create_visit_vital_sign'), hasLength(2));

      final createParams = client.rpcCalls
          .where((call) => call.fn == 'create_visit_vital_sign')
          .map((call) => call.params)
          .toList(growable: false);
      expect(
        createParams,
        containsAll([
          {
            'p_visit_id': encounterTestVisitId,
            'p_name': 'Blood Pressure',
            'p_value': '120/80',
            'p_unit': 'mmHg',
          },
          {
            'p_visit_id': encounterTestVisitId,
            'p_name': 'Heart Rate',
            'p_value': '72',
            'p_unit': 'bpm',
          },
        ]),
      );

      final after = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(after.encounterDraft.isEmpty, isTrue);
      expect(after.persistedVisit.vitalSigns, hasLength(2));
      expect(
        after.persistedVisit.vitalSigns.map((sign) => sign.name).toSet(),
        {'Blood Pressure', 'Heart Rate'},
      );
    });
  });
}

class _NoOpStorageBucket extends Fake implements StorageFileApi {}

class _NoOpAttachmentStorageTestClient extends Fake implements SupabaseClient {
  @override
  SupabaseStorageClient get storage => _NoOpFakeStorageClient();
}

class _NoOpFakeStorageClient extends Fake implements SupabaseStorageClient {
  @override
  StorageFileApi from(String id) => _NoOpStorageBucket();
}

/// Tracks created vitals and returns them from subsequent [get_visit] calls.
class _DeferredPersistenceRpcClient extends VisitRpcTestClient {
  final List<Map<String, dynamic>> persistedVitals = [];
  var _nextVitalSeq = 0;

  Map<String, dynamic> _visitPayload(String visitId) {
    return {
      'id': visitId,
      'branch_id': encounterTestBranchId,
      'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': encounterTestPatientId,
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Test',
      'visit_date': '2026-05-31',
      'status': 'in_progress',
      'updated_at': '2026-05-31T10:00:00.000Z',
      'documentation': {
        'complaint': null,
        'history': null,
        'examination': null,
        'diagnosis': null,
        'plan': null,
        'updated_at': '2026-05-31T10:00:00.000Z',
      },
      if (persistedVitals.isNotEmpty) 'vital_signs': persistedVitals,
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_visit_vital_sign') {
      _nextVitalSeq++;
      final vitalId = '11111111-1111-4111-8111-${_nextVitalSeq.toString().padLeft(12, '0')}';
      persistedVitals.add({
        'id': vitalId,
        'name': params?['p_name'],
        'value': params?['p_value'],
        'unit': params?['p_unit'],
        if (params?['p_predefined_vital_sign_id'] != null)
          'predefined_vital_sign_id': params?['p_predefined_vital_sign_id'],
      });
      rpcResults['create_visit_vital_sign'] = {
        'success': true,
        'data': {'vital_sign_id': vitalId},
      };
    }
    if (fn == 'get_visit') {
      final visitId = params?['p_visit_id']?.toString() ?? encounterTestVisitId;
      rpcResults['get_visit'] = {'success': true, 'data': _visitPayload(visitId)};
    }
    return super.rpc(fn, params: params, get: get);
  }
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
