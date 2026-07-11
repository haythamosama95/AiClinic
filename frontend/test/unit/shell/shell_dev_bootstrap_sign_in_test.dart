import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_bootstrap_sign_in.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart' as domain;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('ShellDevBootstrapSignIn', () {
    test('returns null when already authenticated', () async {
      if (!kDebugMode) {
        return;
      }

      final sessionNotifier = TestAuthSessionNotifier();
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(() => sessionNotifier)]);
      addTearDown(container.dispose);
      container.read(authSessionProvider);
      sessionNotifier.setAuthenticated();

      final error = await ShellDevBootstrapSignIn.ensureSignedInWithReader(container.read);

      expect(error, isNull);
    });

    test('signs in as bootstrap admin when unauthenticated', () async {
      if (!kDebugMode) {
        return;
      }

      var signInCalled = false;
      final sessionNotifier = _BootstrapSignInTestNotifier();

      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => sessionNotifier),
          authRepositoryProvider.overrideWith(
            (ref) => _RecordingAuthRepository(
              onSignIn: () {
                signInCalled = true;
                sessionNotifier.authenticateOnSync = true;
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(authSessionProvider);

      final error = await ShellDevBootstrapSignIn.ensureSignedInWithReader(container.read);

      expect(error, isNull);
      expect(signInCalled, isTrue);
      expect(container.read(authSessionProvider).isAuthenticated, isTrue);
    });
  });
}

class _BootstrapSignInTestNotifier extends TestAuthSessionNotifier {
  var authenticateOnSync = false;

  @override
  Future<void> syncAfterSignIn() async {
    if (authenticateOnSync) {
      setAuthenticated();
      authenticateOnSync = false;
    }
  }
}

class _RecordingAuthRepository implements domain.AuthRepository {
  _RecordingAuthRepository({required void Function() onSignIn}) : _onSignIn = onSignIn;

  final void Function() _onSignIn;

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Future<void> clearPersistedSessionOnColdStart() async {}

  @override
  Future<void> refreshSession() async {}

  @override
  Future<void> signIn({required String username, required String password}) async {
    _onSignIn();
  }

  @override
  Future<void> signOut() async {}
}
