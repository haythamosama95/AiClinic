import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _IdleHarnessRepository extends AuthRepository {
  _IdleHarnessRepository() : super(_FakeClient());

  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _FakeClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _HarnessAuthNotifier extends AuthSessionNotifier {
  @override
  AuthSessionState build() => const AuthSessionState(status: AuthSessionStatus.unauthenticated);
}

void main() {
  test('signOutDueToInactivity clears session with idle message', () async {
    late _IdleHarnessRepository repo;

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => repo = _IdleHarnessRepository()),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_HarnessAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _HarnessAuthNotifier;
    notifier.state = AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext());
    container.read(idleTimeoutServiceProvider).enable(resetTimer: true);

    await notifier.signOutDueToInactivity();

    expect(repo.signOutCalls, 1);
    expect(container.read(authSessionProvider).isAuthenticated, isFalse);
    expect(container.read(authSessionProvider).failureMessage, kIdleTimeoutSignOutMessage);
    expect(container.read(idleTimeoutServiceProvider).isEnabled, isFalse);
  });

  test('explicit signOut disables idle monitoring without session-ended message', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => _IdleHarnessRepository()),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_HarnessAuthNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _HarnessAuthNotifier;
    notifier.state = AuthSessionState(status: AuthSessionStatus.authenticated, context: sampleAuthSessionContext());
    container.read(idleTimeoutServiceProvider).enable(resetTimer: true);

    await notifier.signOut();

    expect(container.read(authSessionProvider).failureMessage, isNull);
    expect(container.read(idleTimeoutServiceProvider).isEnabled, isFalse);
  });
}
