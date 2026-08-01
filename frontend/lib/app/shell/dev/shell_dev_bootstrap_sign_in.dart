import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/presentation/dev/auth_dev_widgets.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';

typedef DevToolReader = T Function<T>(ProviderListenable<T> provider);

/// Signs in as the local bootstrap administrator when dev tooling needs an RPC session.
abstract final class ShellDevBootstrapSignIn {
  const ShellDevBootstrapSignIn._();

  /// Returns an error message when sign-in fails, or null when a session is ready.
  static Future<String?> ensureSignedIn(WidgetRef ref) => ensureSignedInWithReader(ref.read);

<<<<<<< HEAD
  @visibleForTesting
=======
  /// Same as [ensureSignedIn] for notifiers and other [Ref]-only contexts.
  static Future<String?> ensureSignedInWithRef(Ref ref) => ensureSignedInWithReader(ref.read);

>>>>>>> master
  static Future<String?> ensureSignedInWithReader(DevToolReader read) async {
    if (!kDebugMode) {
      return 'Dev tools are not available in release builds.';
    }

    if (read(authSessionProvider).isAuthenticated) {
      return null;
    }

    try {
      await read(authSessionProvider.notifier).ensureReadyForSignIn();
      await read(
        authRepositoryProvider,
      ).signIn(username: AuthDevBootstrapCredentials.username, password: AuthDevBootstrapCredentials.password);
      await read(authSessionProvider.notifier).syncAfterSignIn();
      return _waitForAuthenticatedSession(read);
    } on AuthException {
      return kGenericSignInFailureMessage;
    } on StateError {
      return kSignInNotReadyMessage;
    } catch (error) {
      final details = error.toString().toLowerCase();
      if (details.contains('postgrest') || details.contains('jwt') || details.contains('permission denied')) {
        return kSignInUnavailableMessage;
      }
      return kSignInUnavailableMessage;
    }
  }

  static Future<String?> _waitForAuthenticatedSession(DevToolReader read) async {
    const attempts = 150;
    for (var i = 0; i < attempts; i++) {
      final session = read(authSessionProvider);
      if (session.isAuthenticated) {
        return null;
      }

      if (session.status == AuthSessionStatus.unauthenticated && session.failureMessage != null) {
        return session.failureMessage;
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    return 'Sign-in is taking longer than expected. Wait a moment and try again.';
  }
}
