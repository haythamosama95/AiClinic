import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier hydrateFromBackend', () {
    test('skips hydration while bootstrap setup is required', () async {
      final auth = MutableAuthSessionNotifier(bootstrapAdminSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = sampleHydratedDraft();

      await container.read(clinicSetupProvider.notifier).hydrateFromBackend();
      await flushMicrotasks();

      expect(orchestrator.hydrateDraftFromBackendCalls, 0);
      expect(container.read(clinicSetupProvider).draft.organization.name, '');
    });

    test('skips hydration when session context is absent', () async {
      final auth = MutableAuthSessionNotifier(const AuthSessionState(status: AuthSessionStatus.unknown));
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = sampleHydratedDraft();

      await container.read(clinicSetupProvider.notifier).hydrateFromBackend();

      expect(orchestrator.hydrateDraftFromBackendCalls, 0);
    });

    test('applies orchestrator draft and confirmed entity ids', () async {
      final auth = MutableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final hydrated = sampleHydratedDraft();
      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = hydrated;

      await container.read(clinicSetupProvider.notifier).hydrateFromBackend();
      await flushMicrotasks();

      expect(orchestrator.hydrateDraftFromBackendCalls, 1);

      final state = container.read(clinicSetupProvider);
      expect(state.draft.organization.name, 'Test Clinic');
      expect(state.draft.branches.single.name, 'Main');
      expect(state.draft.staff.single.name, 'Admin');
      expect(state.draft.services.single.name, 'Consultation');
      expect(state.confirmedBranchIds, contains(hydrated.branches.single.id));
      expect(state.confirmedStaffIds, contains(hydrated.staff.single.id));
      expect(state.confirmedServiceIds, contains(hydrated.services.single.id));
      expect(state.submitError, isNull);

      final prefs = await readAllSetupPrefs();
      expect(prefs.containsKey(setupDraftPrefsKey), isTrue);
    });

    test('no-ops when orchestrator returns null draft', () async {
      final auth = MutableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = null;

      await container.read(clinicSetupProvider.notifier).hydrateFromBackend();

      expect(orchestrator.hydrateDraftFromBackendCalls, 1);
      expect(container.read(clinicSetupProvider).draft.organization.name, '');
    });
  });
}
