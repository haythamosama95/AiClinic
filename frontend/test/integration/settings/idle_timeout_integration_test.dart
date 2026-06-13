import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';

class _FakeIdleStore extends IdleTimeoutPreferencesStore {
  _FakeIdleStore(this.duration);

  Duration duration;

  @override
  Future<Duration> loadIdleDuration() async => duration;

  @override
  Future<void> saveIdleDuration(Duration duration) async {
    this.duration = duration;
  }
}

void main() {
  test('idle timeout triggers sign-out after duration elapses', () {
    FakeAsync().run((async) {
      var signedOut = false;
      final container = ProviderContainer(
        overrides: [
          idleTimeoutPreferencesStoreProvider.overrideWithValue(_FakeIdleStore(const Duration(seconds: 5))),
          idleTimeoutServiceProvider.overrideWith((ref) {
            final idle = IdleTimeoutService(
              idleDuration: const Duration(seconds: 5),
              onIdleTimeout: () => signedOut = true,
            );
            ref.onDispose(idle.dispose);
            return idle;
          }),
        ],
      );
      addTearDown(container.dispose);

      container.read(idleTimeoutServiceProvider).enable(resetTimer: true);
      async.elapse(const Duration(seconds: 5));
      expect(signedOut, isTrue);
    });
  });

  test('user activity resets idle timer', () {
    FakeAsync().run((async) {
      var signedOut = false;
      final service = IdleTimeoutService(
        idleDuration: const Duration(seconds: 30),
        onIdleTimeout: () => signedOut = true,
      );
      addTearDown(service.dispose);

      service.enable(resetTimer: true);
      async.elapse(const Duration(seconds: 25));
      service.recordActivity();
      async.elapse(const Duration(seconds: 25));
      expect(signedOut, isFalse);
      async.elapse(const Duration(seconds: 5));
      expect(signedOut, isTrue);
    });
  });
}
