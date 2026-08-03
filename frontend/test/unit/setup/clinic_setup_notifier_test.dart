import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_test_support.dart';
import 'clinic_setup_notifier_support.dart';

void main() {
  group('isSetupCompleteProvider', () {
    test('returns false while bootstrap setup is required', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(() => auth)]);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(isSetupCompleteProvider), isFalse);
    });

    test('follows local completed flag after server setup is complete', () async {
      SharedPreferences.setMockInitialValues({setupCompletePrefsKey: 'true'});
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: false),
        ),
      );
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(() => auth)]);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(isSetupCompleteProvider), isTrue);

      await container.read(clinicSetupProvider.notifier).resetSetup();

      expect(container.read(isSetupCompleteProvider), isFalse);
      expect(container.read(clinicSetupProvider).completed, isFalse);
      expect(container.read(clinicSetupProvider).step, 0);
    });
  });

  group('isBootstrapSetupRequiredProvider', () {
    test('returns true when session needs clinic setup', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(isBootstrapSetupRequiredProvider), isTrue);
    });

    test('returns false when session has completed bootstrap', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: false),
        ),
      );
      final container = createClinicSetupContainer(
        prefs: {setupCompletePrefsKey: 'true'},
        auth: auth,
      );
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(isBootstrapSetupRequiredProvider), isFalse);
    });

    test('falls back to local wizard progress when session context is absent', () async {
      final auth = MutableAuthSessionNotifier(const AuthSessionState(status: AuthSessionStatus.unknown));
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(isBootstrapSetupRequiredProvider), isTrue);

      final notifier = container.read(clinicSetupProvider.notifier);
      notifier.markStepComplete(0);
      await container.read(clinicSetupProvider.notifier).persistDraft();
      container.read(clinicSetupProvider.notifier).markSetupComplete();
      await flushMicrotasks();

      expect(container.read(isBootstrapSetupRequiredProvider), isFalse);
    });
  });
}
