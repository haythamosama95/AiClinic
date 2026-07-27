import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';

/// Verifies the billing handoff invariant: flush before navigation.
void main() {
  group('Visit billing handoff', () {
    test('saveAll runs before billing navigation would proceed', () async {
      final persisted = sampleEncounterVisit().copyWith(
        documentation: const VisitClinicalNote(),
      );
      final dirtyState = VisitDocumentationState(
        persistedVisit: persisted,
        complaint: 'Headache',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: persisted.updatedAt ?? persisted.visitDate,
      );
      final trackingNotifier = _HandoffTrackingNotifier(dirtyState);

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  branchIds: [encounterTestBranchId],
                  activeBranchId: encounterTestBranchId,
                  permissions: {
                    PermissionKeys.visitsEditSoap,
                    PermissionKeys.visitsCreate,
                    PermissionKeys.invoicesCreate,
                  },
                ),
              ),
            ),
          ),
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => trackingNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final docState = container.read(visitDocumentationProvider(encounterTestVisitId)).requireValue;
      expect(docState.hasUnsavedChanges, isTrue);

      final saved = await container.read(visitDocumentationProvider(encounterTestVisitId).notifier).saveAll();
      expect(saved, isTrue);
      expect(trackingNotifier.saveAllCalls, 1);
    });

    test('failed saveAll blocks billing handoff', () async {
      final persisted = sampleEncounterVisit().copyWith(
        documentation: const VisitClinicalNote(),
      );
      final dirtyState = VisitDocumentationState(
        persistedVisit: persisted,
        complaint: 'Headache',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
        expectedUpdatedAt: persisted.updatedAt ?? persisted.visitDate,
      );
      final trackingNotifier = _HandoffTrackingNotifier(dirtyState)..saveAllResult = false;

      final container = ProviderContainer(
        overrides: [
          visitDocumentationProvider(encounterTestVisitId).overrideWith(() => trackingNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(visitDocumentationProvider(encounterTestVisitId).future);
      final saved = await container.read(visitDocumentationProvider(encounterTestVisitId).notifier).saveAll();

      expect(saved, isFalse);
      expect(trackingNotifier.saveAllCalls, 1);
    });
  });
}

class _HandoffTrackingNotifier extends VisitDocumentationNotifier {
  _HandoffTrackingNotifier(this._state) : super(encounterTestVisitId);

  final VisitDocumentationState _state;
  int saveAllCalls = 0;
  bool saveAllResult = true;

  @override
  Future<VisitDocumentationState> build() async => _state;

  @override
  Future<bool> saveAll() async {
    saveAllCalls++;
    return saveAllResult;
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
