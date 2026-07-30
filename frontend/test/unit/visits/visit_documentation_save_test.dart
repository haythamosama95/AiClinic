import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart' show VisitClinicalNote, kMaxClinicalSectionLength;
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  late VisitRpcTestClient client;
  final sessionToken = DateTime.utc(2026, 5, 31, 10);
  final savedToken = DateTime.utc(2026, 5, 31, 10, 5);

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
        visitAttachmentServiceProvider.overrideWith(
          (ref) => _StubVisitAttachmentService(ref.watch(visitRepositoryProvider)),
        ),
        visitDocumentationProvider(encounterTestVisitId).overrideWith(
          () => _SeededVisitDocumentationNotifier(seedState),
        ),
      ],
    );
  }

  VisitDocumentationState draftState({String complaint = 'Edited complaint'}) {
    final persisted = sampleEncounterVisit(
      documentation: VisitClinicalNote(updatedAt: sessionToken),
    );
    return VisitDocumentationState(
      visit: persisted,
      persistedVisit: persisted,
      complaint: complaint,
      history: '',
      examination: '',
      diagnosis: '',
      plan: '',
      expectedUpdatedAt: sessionToken,
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
    client.rpcResults['save_visit_documentation'] = {
      'success': true,
      'data': {
        'visit_id': encounterTestVisitId,
        'updated_at': savedToken.toUtc().toIso8601String(),
      },
    };
  });

  group('VisitDocumentationNotifier.save', () {
    test('trivial: idle→saving→saved on successful clinical note persist', () async {
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final statuses = <DocumentationSaveStatus>[];
      container.listen(
        visitDocumentationProvider(encounterTestVisitId),
        (_, next) {
          final value = next.value;
          if (value != null) statuses.add(value.saveStatus);
        },
        fireImmediately: true,
      );
      final notifier = await loadNotifier(container);

      await notifier.save();

      expect(statuses, contains(DocumentationSaveStatus.saving));
      expect(readState(container).saveStatus, DocumentationSaveStatus.saved);
      expect(readState(container).noteEditMode, DocumentationEditMode.readOnly);
      expect(client.rpcCalls.any((c) => c.fn == 'save_visit_documentation'), isTrue);
      expect(
        client.paramsForFunction('save_visit_documentation')?['p_expected_updated_at'],
        sessionToken.toUtc().toIso8601String(),
      );
    });

    test('advanced: forwards trimmed non-empty sections and null for blank sections', () async {
      final container = createContainer(
        draftState().copyWith(complaint: '  Pain  ', history: '   '),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.save();

      final params = client.paramsForFunction('save_visit_documentation');
      expect(params?['p_complaint'], 'Pain');
      expect(params?['p_history'], isNull);
    });

    test('invalid state: section length error transitions to error without RPC', () async {
      final oversized = 'x' * (kMaxClinicalSectionLength + 1);
      final container = createContainer(draftState(complaint: oversized));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.save();

      expect(readState(container).saveStatus, DocumentationSaveStatus.error);
      expect(readState(container).errorMessage, isNotNull);
      expect(client.rpcCalls.where((c) => c.fn == 'save_visit_documentation'), isEmpty);
    });

    test('edge case: RPC failure transitions saving→error with visit message', () async {
      client.rpcResults['save_visit_documentation'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.save();

      final state = readState(container);
      expect(state.saveStatus, DocumentationSaveStatus.error);
      expect(
        state.errorMessage,
        visitMessageForRpc(
          RpcFailure(const RpcResult(success: false, errorCode: 'FORBIDDEN', errorMessage: 'Denied')),
        ),
      );
    });

    test('stupid usage: save with nothing dirty still persists and refreshes token', () async {
      final visit = sampleEncounterVisit(documentation: VisitClinicalNote(updatedAt: sessionToken, complaint: 'Same'));
      final synced = VisitDocumentationState(
        visit: visit,
        persistedVisit: visit,
        complaint: 'Same',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: sessionToken,
      );
      final container = createContainer(synced);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.save();

      expect(readState(container).saveStatus, DocumentationSaveStatus.saved);
      expect(readState(container).expectedUpdatedAt, savedToken);
    });

    test('invalid state: completed visit in viewing mode does not save', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit).copyWith(complaint: 'Edited');
      final container = createContainer(state);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.save();

      expect(client.rpcCalls.where((c) => c.fn == 'save_visit_documentation'), isEmpty);
      expect(readState(container).complaint, 'Edited');
    });
  });

  group('VisitDocumentationNotifier.saveAll', () {
    test('trivial: returns true immediately when nothing needs persist', () async {
      final visit = sampleEncounterVisit(documentation: VisitClinicalNote(updatedAt: sessionToken));
      final synced = VisitDocumentationState(
        visit: visit,
        persistedVisit: visit,
        complaint: '',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: sessionToken,
      );
      final container = createContainer(synced);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      expect(client.rpcCalls, isEmpty);
    });

    test('advanced: flushes encounter draft before clinical note save', () async {
      final container = createContainer(
        draftState().copyWith(
          encounterDraft: buildVisitEncounterDraft(
            pendingVitalSigns: [buildVisitVitalSign(id: 'draft:vs-1', name: 'Temp', value: '38')],
          ),
        ),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      final createIndex = client.rpcCalls.indexWhere((c) => c.fn == 'create_visit_vital_sign');
      final saveIndex = client.rpcCalls.indexWhere((c) => c.fn == 'save_visit_documentation');
      expect(createIndex, greaterThanOrEqualTo(0));
      expect(saveIndex, greaterThan(createIndex));
      expect(readState(container).encounterDraft.isEmpty, isTrue);
      expect(readState(container).saveStatus, DocumentationSaveStatus.saved);
    });

    test('advanced: structured-only flush settles saveStatus to saved', () async {
      final visit = sampleEncounterVisit(documentation: VisitClinicalNote(updatedAt: sessionToken));
      final container = createContainer(
        VisitDocumentationState(
          visit: visit,
          persistedVisit: visit,
          complaint: '',
          history: '',
          examination: '',
          diagnosis: '',
          plan: '',
          expectedUpdatedAt: sessionToken,
          encounterDraft: buildVisitEncounterDraft(
            pendingVitalSigns: [buildVisitVitalSign(id: 'draft:vs-1', name: 'Temp', value: '38')],
          ),
        ),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final saved = await notifier.saveAll();

      expect(saved, isTrue);
      expect(readState(container).saveStatus, DocumentationSaveStatus.saved);
      expect(client.rpcCalls.any((c) => c.fn == 'save_visit_documentation'), isFalse);
    });

    test('regression: draft-flush partial failure preserves staged overlay and surfaces error', () async {
      client.rpcResults['create_visit_vital_sign'] = {
        'success': false,
        'error_code': 'INVALID_INPUT',
        'error_message': 'Failed vital',
      };
      final draft = buildVisitEncounterDraft(
        pendingVitalSigns: [buildVisitVitalSign(id: 'draft:vs-1', name: 'Temp', value: '38')],
      );
      final container = createContainer(draftState().copyWith(encounterDraft: draft));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final saved = await notifier.saveAll();

      expect(saved, isFalse);
      final state = readState(container);
      expect(state.saveStatus, DocumentationSaveStatus.error);
      expect(state.errorMessage, contains('Some changes may have been saved'));
      expect(state.encounterDraft.pendingVitalSigns, hasLength(1));
      expect(state.complaint, 'Edited complaint');
    });

    test('edge case: re-entrant saveAll while first call in flight returns based on final state', () async {
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final first = notifier.saveAll();
      final second = notifier.saveAll();
      final results = await Future.wait([first, second]);

      expect(results, everyElement(isTrue));
      expect(readState(container).saveStatus, DocumentationSaveStatus.saved);
    });
  });

  group('VisitDocumentationNotifier.completeVisit', () {
    test('trivial: completes in-progress visit after saveAll when draft dirty', () async {
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      final result = await notifier.completeVisit();

      expect(result.visitId, encounterTestVisitId);
      expect(client.rpcCalls.any((c) => c.fn == 'complete_visit'), isTrue);
      final state = readState(container);
      expect(state.workspaceEditMode, WorkspaceEditMode.viewing);
      expect(state.noteEditMode, DocumentationEditMode.readOnly);
      expect(state.saveStatus, DocumentationSaveStatus.saved);
    });

    test('advanced: canSubmitVisit gates completeVisit', () async {
      final completed = sampleEncounterVisit(status: VisitStatus.completed);
      final container = createContainer(VisitDocumentationState.fromVisit(completed));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      expect(notifier.canSubmitVisit(readState(container).visit), isFalse);
      await expectLater(
        () => notifier.completeVisit(),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('invalid state: completeVisit on completed visit throws INVALID_INPUT', () async {
      final completed = sampleEncounterVisit(status: VisitStatus.completed);
      final container = createContainer(VisitDocumentationState.fromVisit(completed));
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await expectLater(
        notifier.completeVisit(),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
      expect(client.rpcCalls.where((c) => c.fn == 'complete_visit'), isEmpty);
    });

    test('advanced: uses refreshed expectedUpdatedAt token after pre-submit saveAll', () async {
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.completeVisit(expectedUpdatedAt: DateTime.utc(2020));

      expect(
        client.paramsForFunction('complete_visit')?['p_expected_updated_at'],
        savedToken.toUtc().toIso8601String(),
      );
    });
  });

  group('VisitDocumentationNotifier edit modes', () {
    test('trivial: enterEditMode switches note to editing when permitted', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit);
      final container = createContainer(state);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.enterEditMode();

      expect(readState(container).noteEditMode, DocumentationEditMode.editing);
    });

    test('advanced: enterWorkspaceEditMode enables workspace and note editing', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final state = VisitDocumentationState.fromVisit(visit).copyWith(errorMessage: 'Old');
      final container = createContainer(state);
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.enterWorkspaceEditMode();

      final next = readState(container);
      expect(next.workspaceEditMode, WorkspaceEditMode.editing);
      expect(next.noteEditMode, DocumentationEditMode.editing);
      expect(next.errorMessage, isNull);
    });

    test('invalid state: enterEditMode without permission is a no-op', () async {
      final visit = sampleEncounterVisit(status: VisitStatus.completed);
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  branchIds: ['other-branch'],
                  permissions: {PermissionKeys.visitsEditSoap},
                ),
              ),
            ),
          ),
          visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _SeededVisitDocumentationNotifier(VisitDocumentationState.fromVisit(visit)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);
      expect(readState(container).noteEditMode, DocumentationEditMode.readOnly);

      notifier.enterEditMode();

      expect(readState(container).noteEditMode, DocumentationEditMode.readOnly);
    });
  });

  group('VisitDocumentationNotifier clinical note flush callbacks', () {
    test('trivial: registered callback invoked before save via prepareEncounterReview', () async {
      var flushed = false;
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);
      notifier.registerClinicalNoteFlush(() => flushed = true);

      await notifier.saveAll();

      expect(flushed, isTrue);
    });

    test('advanced: unregistered callback is not invoked', () async {
      var count = 0;
      void callback() => count++;
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);
      notifier.registerClinicalNoteFlush(callback);
      notifier.unregisterClinicalNoteFlush(callback);

      notifier.prepareEncounterReview();

      expect(count, 0);
    });

    test('stupid usage: unregister of unregistered callback does not throw', () async {
      final container = createContainer(draftState());
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      expect(() => notifier.unregisterClinicalNoteFlush(() {}), returnsNormally);
    });
  });

  group('VisitDocumentationNotifier refresh and reload', () {
    test('advanced: refreshVisitPreservingDraft keeps complaint draft while updating persisted visit', () async {
      final persisted = sampleEncounterVisit(documentation: VisitClinicalNote(updatedAt: sessionToken));
      final container = createContainer(
        VisitDocumentationState(
          visit: persisted,
          persistedVisit: persisted,
          complaint: 'Draft text',
          history: '',
          examination: '',
          diagnosis: '',
          plan: '',
          expectedUpdatedAt: sessionToken,
        ),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      await notifier.refreshVisitPreservingDraft();

      final state = readState(container);
      expect(state.complaint, 'Draft text');
      expect(state.persistedVisit.id, encounterTestVisitId);
      expect(client.rpcCalls.where((c) => c.fn == 'get_visit'), isNotEmpty);
    });

    test('advanced: reloadVisit replaces state from repository', () async {
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
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      notifier.updateComplaint('Local draft');

      await notifier.reloadVisit();

      final state = readState(container);
      expect(state.complaint, '');
      expect(state.encounterDraft.isEmpty, isTrue);
    });

    test('advanced: reloadAfterStale reloads repository and clears stale marker', () async {
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
        ],
      );
      addTearDown(container.dispose);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      notifier.updateComplaint('Stale draft');

      await notifier.reloadAfterStale();

      final state = readState(container);
      expect(state.saveStatus, DocumentationSaveStatus.idle);
      expect(state.complaint, '');
    });
  });

  group('VisitDocumentationNotifier.updateDraft', () {
    test('trivial: updateComplaint marks draft dirty and resets save status', () async {
      final visit = sampleEncounterVisit(documentation: VisitClinicalNote(updatedAt: sessionToken));
      final container = createContainer(
        VisitDocumentationState(
          visit: visit,
          persistedVisit: visit,
          complaint: '',
          history: '',
          examination: '',
          diagnosis: '',
          plan: '',
          expectedUpdatedAt: sessionToken,
          saveStatus: DocumentationSaveStatus.saved,
        ),
      );
      addTearDown(container.dispose);
      final notifier = await loadNotifier(container);

      notifier.updateComplaint('New complaint');

      final state = readState(container);
      expect(state.complaint, 'New complaint');
      expect(state.saveStatus, DocumentationSaveStatus.idle);
      expect(state.errorMessage, isNull);
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

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _StubVisitAttachmentService extends VisitAttachmentService {
  _StubVisitAttachmentService(VisitRepository repository) : super(_FakeSupabaseClient(), repository);
}
