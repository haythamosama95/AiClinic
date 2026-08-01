import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/application/setup_rpc_messages.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier resetInstallationForDevelopment', () {
    test('returns false outside debug builds', () async {
      if (!kDebugMode) {
        final auth = RefreshableAuthSessionNotifier(steadyStateSession());
        final bootstrapRepo = FakeBootstrapRepository(
          onResetInstallation: () => Future.value(const RpcResult(success: true, data: {})),
        );
        final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
        addTearDown(container.dispose);
        await pumpDraftLoad(container);

        final ok = await container.read(clinicSetupProvider.notifier).resetInstallationForDevelopment();

        expect(ok, isFalse);
      } else {
        expect(kDebugMode, isTrue);
      }
    });

    test('debug success resets installation and local setup state', () async {
      if (!kDebugMode) {
        return;
      }

      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final bootstrapRepo = FakeBootstrapRepository(
        onResetInstallation: () => Future.value(
          const RpcResult(
            success: true,
            data: {'organizations_deleted': 1, 'branches_deleted': 2},
          ),
        ),
      );
      final container = createClinicSetupContainer(
        prefs: {setupCompletePrefsKey: 'true'},
        auth: auth,
        bootstrapRepository: bootstrapRepo,
      );
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final orchestrator = readFakeOrchestrator(container);
      final notifier = container.read(clinicSetupProvider.notifier);
      notifier.markStepComplete(0);
      notifier.state = notifier.state.copyWith(completed: true, step: 2);

      final ok = await notifier.resetInstallationForDevelopment();
      await flushMicrotasks();

      expect(ok, isTrue);
      expect(auth.refreshSessionContextCalls, 1);
      expect(orchestrator.notifyClinicDataChangedCalls, 1);

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isFalse);
      expect(state.step, 0);
      expect(state.isSubmitting, isFalse);
      expect(state.completedSteps, isEmpty);
    });

    test('returns false when already submitting', () async {
      if (!kDebugMode) {
        return;
      }

      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final bootstrapRepo = FakeBootstrapRepository(
        onResetInstallation: () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const RpcResult(success: true, data: {});
        },
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final notifier = container.read(clinicSetupProvider.notifier);
      final first = notifier.resetInstallationForDevelopment();
      final second = await notifier.resetInstallationForDevelopment();

      expect(second, isFalse);
      await first;
    });

    test('surfaces RpcFailure message on reset failure', () async {
      if (!kDebugMode) {
        return;
      }

      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final bootstrapRepo = FakeBootstrapRepository(
        onResetInstallation: () => Future.error(rpcFailure('RESET_INCOMPLETE')),
      );
      final container = createClinicSetupContainer(auth: auth, bootstrapRepository: bootstrapRepo);
      addTearDown(container.dispose);
      await pumpDraftLoad(container);

      final ok = await container.read(clinicSetupProvider.notifier).resetInstallationForDevelopment();

      expect(ok, isFalse);
      expect(
        container.read(clinicSetupProvider).submitError,
        setupMessageForRpc(rpcFailure('RESET_INCOMPLETE')),
      );
      expect(container.read(clinicSetupProvider).isSubmitting, isFalse);
    });
  });
}
