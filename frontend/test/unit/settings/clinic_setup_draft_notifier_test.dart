import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_draft_notifier.dart';
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

      await container.read(clinicSetupDraftProvider.notifier).resetSetup();

      expect(container.read(isSetupCompleteProvider), isFalse);
      expect(container.read(clinicSetupDraftProvider).completed, isFalse);
      expect(container.read(clinicSetupDraftProvider).step, 0);
    });
  });
}

Future<void> _pumpDraftLoad(ProviderContainer container) async {
  container.read(clinicSetupDraftProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
