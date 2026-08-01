import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/setup/application/provisioning_rpc_messages.dart';
import 'package:ai_clinic/features/setup/application/setup_rpc_messages.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier completeSetup', () {
    test('returns false when already submitting', () async {
      final auth = RefreshableAuthSessionNotifier(bootstrapAdminSession(), refreshToSteadyState: true);
      final bootstrapRepo = FakeBootstrapRepository(
        onFinishSetup: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return defaultBootstrapResult();
        },
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final notifier = container.read(clinicSetupProvider.notifier);
      seedValidBootstrapDraft(notifier);
      final first = notifier.completeSetup();
      final second = await notifier.completeSetup();

      expect(second, isFalse);
      expect(container.read(clinicSetupProvider).isSubmitting, isTrue);

      await first;
      await flushMicrotasks();
    });

    test('rejects bootstrap completion for non-admin staff', () async {
      final auth = MutableAuthSessionNotifier(nonBootstrapStaffSession());
      final bootstrapRepo = FakeBootstrapRepository(
        onFinishSetup: (_) => Future.value(defaultBootstrapResult()),
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();

      expect(ok, isFalse);
      expect(
        container.read(clinicSetupProvider).submitError,
        'Only the clinic administrator account can run first-time setup.',
      );
      expect(bootstrapRepo.lastFinishSetupInput, isNull);
    });

    test('bootstrap success persists, hydrates, and marks complete', () async {
      final auth = RefreshableAuthSessionNotifier(bootstrapAdminSession(), refreshToSteadyState: true);
      final bootstrapRepo = FakeBootstrapRepository(
        onFinishSetup: (_) async => defaultBootstrapResult(),
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      seedValidBootstrapDraft(container.read(clinicSetupProvider.notifier));
      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = sampleHydratedDraft();

      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();
      await flushMicrotasks();

      expect(ok, isTrue);
      expect(bootstrapRepo.lastFinishSetupInput, isNotNull);
      expect(
        (container.read(authSessionProvider.notifier) as RefreshableAuthSessionNotifier).refreshSessionContextCalls,
        1,
      );
      expect(orchestrator.hydrateDraftFromBackendCalls, 1);
      expect(orchestrator.notifyClinicDataChangedCalls, 1);

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isTrue);
      expect(state.isSubmitting, isFalse);
      expect(state.completedSteps, {0, 1, 2, 3});
      expect(state.draft.organization.name, 'Test Clinic');

      final prefs = await readAllSetupPrefs();
      expect(prefs[setupCompletePrefsKey], 'true');
    });

    test('bootstrap calls persistRemainingBootstrapEntities for extra entities', () async {
      final auth = RefreshableAuthSessionNotifier(bootstrapAdminSession(), refreshToSteadyState: true);
      final bootstrapRepo = FakeBootstrapRepository(
        onFinishSetup: (_) async => defaultBootstrapResult(),
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final notifier = container.read(clinicSetupProvider.notifier);
      seedValidBootstrapDraft(notifier);
      notifier.addBranch();
      notifier.addService();
      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = sampleHydratedDraft();

      await notifier.completeSetup();
      await flushMicrotasks();

      expect(orchestrator.persistRemainingBootstrapEntitiesCalls, 1);
    });

    test('bootstrap RpcFailure surfaces provisioning message for USERNAME_EXISTS', () async {
      final auth = RefreshableAuthSessionNotifier(bootstrapAdminSession(), refreshToSteadyState: true);
      final bootstrapRepo = FakeBootstrapRepository(
        onFinishSetup: (_) => Future.error(rpcFailure('USERNAME_EXISTS')),
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      seedValidBootstrapDraft(container.read(clinicSetupProvider.notifier));
      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();

      expect(ok, isFalse);
      expect(
        container.read(clinicSetupProvider).submitError,
        provisioningMessageForRpc(rpcFailure('USERNAME_EXISTS')),
      );
      expect(container.read(clinicSetupProvider).isSubmitting, isFalse);
    });

    test('steady-state success persists via orchestrator and hydrates', () async {
      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      orchestrator.hydrateResult = sampleHydratedDraft();

      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();
      await flushMicrotasks();

      expect(ok, isTrue);
      expect(orchestrator.persistSteadyStateCalls, 1);
      expect(orchestrator.hydrateDraftFromBackendCalls, 1);
      expect(orchestrator.notifyClinicDataChangedCalls, 1);
      expect(container.read(clinicSetupProvider).completed, isTrue);
    });

    test('steady-state rejects when session context is missing', () async {
      final auth = MutableAuthSessionNotifier(const AuthSessionState(status: AuthSessionStatus.unauthenticated));
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();

      expect(ok, isFalse);
      expect(container.read(clinicSetupProvider).submitError, 'Sign in again to save clinic setup.');
    });

    test('steady-state RpcFailure hydrates and surfaces setup message', () async {
      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      orchestrator.persistSteadyStateError = rpcFailure('ORG_NOT_FOUND');
      orchestrator.hydrateResult = sampleHydratedDraft();

      final ok = await container.read(clinicSetupProvider.notifier).completeSetup();
      await flushMicrotasks();

      expect(ok, isFalse);
      expect(orchestrator.hydrateDraftFromBackendCalls, 1);
      expect(
        container.read(clinicSetupProvider).submitError,
        setupMessageForRpc(rpcFailure('ORG_NOT_FOUND')),
      );
      expect(container.read(clinicSetupProvider).isSubmitting, isFalse);
      expect(container.read(clinicSetupProvider).draft.organization.name, 'Test Clinic');
    });
  });
}
