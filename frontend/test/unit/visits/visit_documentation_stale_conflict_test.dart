import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  group('H4 stale conflict resolution', () {
    late VisitRpcTestClient client;
    final staleToken = DateTime.utc(2026, 5, 31, 10);
    final serverToken = DateTime.utc(2026, 5, 31, 11);

    setUp(() {
      client = VisitRpcTestClient();
    });

    ProviderContainer createContainer(VisitDocumentationState seed) {
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
          visitDocumentationProvider(encounterTestVisitId).overrideWith(
            () => _SeededVisitDocumentationNotifier(seed),
          ),
        ],
      );
    }

    VisitDocumentationState seededDraft() {
      final persisted = sampleEncounterVisit().copyWith(
        documentation: VisitClinicalNote(updatedAt: staleToken),
      );
      return VisitDocumentationState(
        persistedVisit: persisted,
        complaint: 'Local draft',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: staleToken,
      );
    }

    test('resolveStaleConflict(keepLocalDraft: true) refreshes token and allows save', () async {
      client.rpcResults['save_visit_documentation'] = {
        'success': false,
        'error_code': 'STALE_DOCUMENTATION',
        'error_message': 'Stale',
      };

      final container = createContainer(seededDraft());
      addTearDown(container.dispose);

      final notifier = container.read(visitDocumentationProvider(encounterTestVisitId).notifier);
      await container.read(visitDocumentationProvider(encounterTestVisitId).future);

      expect(await notifier.saveAll(), isFalse);
      expect(container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue.saveStatus,
          DocumentationSaveStatus.stale);

      client.rpcResults['get_visit'] = {
        'success': true,
        'data': {
          'id': encounterTestVisitId,
          'branch_id': encounterTestBranchId,
          'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'patient_id': encounterTestPatientId,
          'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          'doctor_name': 'Dr Test',
          'visit_date': '2026-05-31',
          'status': 'in_progress',
          'updated_at': serverToken.toIso8601String(),
          'documentation': {
            'complaint': 'Server copy',
            'updated_at': serverToken.toIso8601String(),
          },
        },
      };

      await notifier.resolveStaleConflict(keepLocalDraft: true);

      final afterResolve = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(afterResolve.saveStatus, DocumentationSaveStatus.idle);
      expect(afterResolve.expectedUpdatedAt, serverToken);
      expect(afterResolve.complaint, 'Local draft');
      expect(afterResolve.staleServerUpdatedAt, isNull);

      client.rpcResults.remove('save_visit_documentation');
      await notifier.save();
      final afterSave = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(afterSave.saveStatus, DocumentationSaveStatus.saved);
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
