import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Generic sign-in failure copy — must not reveal whether the email exists.
const String kGenericSignInFailureMessage = 'Email or password is incorrect.';

/// User-facing message when sign-in fails for non-credential reasons.
const String kSignInUnavailableMessage = 'Unable to sign in right now. Check clinic connectivity and try again.';

/// Shown when startup has not finished preparing the Supabase client for sign-in.
const String kSignInNotReadyMessage = 'Clinic services are still starting. Wait a moment and try again.';

@immutable
class AuthUiState {
  const AuthUiState({this.isSubmitting = false, this.errorMessage});

  final bool isSubmitting;
  final String? errorMessage;

  AuthUiState copyWith({bool? isSubmitting, String? errorMessage, bool clearError = false}) {
    return AuthUiState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthUiState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthUiState> {
  @override
  AuthUiState build() => const AuthUiState();

  bool validateCredentials({required String email, required String password}) {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return false;
    }

    return password.isNotEmpty;
  }

  Future<void> signIn({required String email, required String password}) async {
    if (!validateCredentials(email: email, password: password)) {
      state = state.copyWith(errorMessage: 'Enter a valid email address and password.');
      return;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      await ref.read(authSessionProvider.notifier).ensureReadyForSignIn();
      await ref.read(authRepositoryProvider).signIn(email: email, password: password);
      await ref.read(authSessionProvider.notifier).syncAfterSignIn();
      await _waitForPostLoginResolution();
    } on AuthException catch (error) {
      AppLog.warning('auth.sign_in.failed category=${_authExceptionCategory(error)}');
      state = state.copyWith(isSubmitting: false, errorMessage: _messageForAuthException(error));
    } on StateError {
      AppLog.warning('auth.sign_in.failed category=not_ready');
      state = state.copyWith(isSubmitting: false, errorMessage: kSignInNotReadyMessage);
    } catch (error) {
      AppLog.warning('auth.sign_in.failed category=${_unexpectedErrorCategory(error)}');
      state = state.copyWith(isSubmitting: false, errorMessage: _messageForUnexpectedSignInError(error));
    }
  }

  static String _authExceptionCategory(AuthException error) {
    final details = '${error.code ?? ''} ${error.message}'.toLowerCase();
    if (details.contains('invalid') || details.contains('credential') || details.contains('password')) {
      return 'invalid_credentials';
    }
    if (details.contains('network') || details.contains('503') || details.contains('timeout')) {
      return 'unavailable';
    }
    return 'auth_error';
  }

  static String _unexpectedErrorCategory(Object error) {
    final details = error.toString().toLowerCase();
    if (details.contains('staff claims') || details.contains('staff profile')) {
      return 'missing_staff_permissions';
    }
    if (details.contains('postgrest') || details.contains('jwt') || details.contains('permission denied')) {
      return 'unavailable';
    }
    return 'unexpected';
  }

  String _messageForUnexpectedSignInError(Object error) {
    final details = error.toString().toLowerCase();
    if (details.contains('staff claims') || details.contains('staff profile')) {
      return 'This account is missing clinic staff permissions. Contact your clinic administrator.';
    }

    if (details.contains('postgrest') || details.contains('jwt') || details.contains('permission denied')) {
      return kSignInUnavailableMessage;
    }

    return kSignInUnavailableMessage;
  }

  String _messageForAuthException(AuthException error) {
    final details = '${error.code ?? ''} ${error.message}'.toLowerCase();
    if (details.contains('invalid') || details.contains('credential') || details.contains('password')) {
      return kGenericSignInFailureMessage;
    }

    return kSignInUnavailableMessage;
  }

  Future<void> _waitForPostLoginResolution() async {
    const attempts = 150;
    for (var i = 0; i < attempts; i++) {
      final session = ref.read(authSessionProvider);
      if (session.status == AuthSessionStatus.authenticated) {
        state = const AuthUiState();
        return;
      }

      if (session.status == AuthSessionStatus.unauthenticated && session.failureMessage != null) {
        state = state.copyWith(isSubmitting: false, errorMessage: session.failureMessage);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    AppLog.warning('auth.sign_in.failed category=post_login_timeout');
    state = state.copyWith(
      isSubmitting: false,
      errorMessage:
          'Sign-in is taking longer than expected. If this continues after a backend update, sign out, restart the app, and try again.',
    );
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  /// Surfaces session-ended or idle-timeout messages on the login screen.
  void showExternalMessage(String message) {
    state = state.copyWith(errorMessage: message);
  }
}
