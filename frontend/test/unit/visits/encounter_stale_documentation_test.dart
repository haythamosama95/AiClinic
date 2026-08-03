import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';
import '../../support/visit_encounter_test_support.dart';

const _staleRpcResult = {
  'success': false,
  'error_code': 'STALE_DOCUMENTATION',
  'error_message': 'Stale',
};

void main() {
  group('INT-003 — Stale documentation on concurrent save (VisitDocumentationNotifier)', () {
    late VisitRpcTestClient client;
    final sessionAExpectedAt = DateTime.utc(2026, 5, 31, 10);

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
          visitDocumentationProvider(
            encounterTestVisitId,
          ).overrideWith(() => _SeededVisitDocumentationNotifier(seedState)),
        ],
      );
    }

    VisitDocumentationState draftWithStaleToken({String draftComplaint = 'Edited by session A'}) {
      final persisted = sampleEncounterVisit().copyWith(
        documentation: VisitClinicalNote(updatedAt: sessionAExpectedAt),
      );
      return VisitDocumentationState(
        visit: persisted,
        persistedVisit: persisted,
        complaint: draftComplaint,
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: sessionAExpectedAt,
      );
    }

    VisitDocumentationState syncedWithStaleToken() {
      final visit = sampleEncounterVisit().copyWith(
        documentation: VisitClinicalNote(updatedAt: sessionAExpectedAt),
      );
      return VisitDocumentationState(
        visit: visit,
        persistedVisit: visit,
        complaint: '',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: sessionAExpectedAt,
        saveStatus: DocumentationSaveStatus.saved,
      );
    }

    setUp(() {
      client = VisitRpcTestClient();
    });

    test('saveAll: forwards stale expectedUpdatedAt and surfaces STALE_DOCUMENTATION', () async {
      client.rpcResults['save_visit_documentation'] = _staleRpcResult;

      final container = createContainer(draftWithStaleToken());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      final saved = await notifier.saveAll();

      expect(saved, isFalse);
      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.saveStatus, DocumentationSaveStatus.stale);
      expect(
        state.errorMessage,
        visitMessageForRpc(
          RpcFailure(const RpcResult(success: false, errorCode: 'STALE_DOCUMENTATION', errorMessage: '')),
        ),
      );
      expect(
        client.paramsForFunction('save_visit_documentation')?['p_expected_updated_at'],
        sessionAExpectedAt.toUtc().toIso8601String(),
      );
    });

    test('completeVisit: throws STALE when pre-submit saveAll hits stale concurrency', () async {
      client.rpcResults['save_visit_documentation'] = _staleRpcResult;

      final container = createContainer(draftWithStaleToken());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      await expectLater(
        () => notifier.completeVisit(expectedUpdatedAt: sessionAExpectedAt),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'STALE_DOCUMENTATION')),
      );

      expect(client.rpcCalls.where((call) => call.fn == 'complete_visit'), isEmpty);
      final state = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(state.saveStatus, DocumentationSaveStatus.stale);
    });

    test('completeVisit: rethrows STALE from complete_visit when draft already synced', () async {
      client.rpcResults['complete_visit'] = _staleRpcResult;

      final container = createContainer(syncedWithStaleToken());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      await expectLater(
        () => notifier.completeVisit(expectedUpdatedAt: sessionAExpectedAt),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'STALE_DOCUMENTATION')),
      );

      expect(client.lastFunction, 'complete_visit');
      expect(
        client.paramsForFunction('complete_visit')?['p_expected_updated_at'],
        sessionAExpectedAt.toUtc().toIso8601String(),
      );
    });

    test('completeVisit: uses state token when expectedUpdatedAt omitted after synced draft', () async {
      client.rpcResults['complete_visit'] = _staleRpcResult;

      final container = createContainer(syncedWithStaleToken());
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);

      await expectLater(
        notifier.completeVisit(),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'STALE_DOCUMENTATION')),
      );

      expect(
        client.paramsForFunction('complete_visit')?['p_expected_updated_at'],
        sessionAExpectedAt.toUtc().toIso8601String(),
      );
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
