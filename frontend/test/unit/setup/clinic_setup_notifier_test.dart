import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_test_support.dart';

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

      await _pumpDraftLoad(container);

      expect(container.read(isSetupCompleteProvider), isFalse);
    });

    test('follows local completed flag after server setup is complete', () async {
      SharedPreferences.setMockInitialValues({'aiclinic:setup-complete': 'true'});
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: false),
        ),
      );
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(() => auth)]);
      addTearDown(container.dispose);

      await _pumpDraftLoad(container);

      expect(container.read(isSetupCompleteProvider), isTrue);

      await container.read(clinicSetupProvider.notifier).resetSetup();

      expect(container.read(isSetupCompleteProvider), isFalse);
      expect(container.read(clinicSetupProvider).completed, isFalse);
      expect(container.read(clinicSetupProvider).step, 0);
    });
  });
}

Future<void> _pumpDraftLoad(ProviderContainer container) async {
  container.read(clinicSetupProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
