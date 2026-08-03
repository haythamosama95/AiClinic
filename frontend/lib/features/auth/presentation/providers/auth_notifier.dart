import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Generic sign-in failure copy — must not reveal whether the username exists.
const String kGenericSignInFailureMessage = 'Username or password is incorrect.';

/// User-facing message when sign-in fails for non-credential reasons.
const String kSignInUnavailableMessage = 'Unable to sign in right now. Check clinic connectivity and try again.';

/// Shown when startup has not finished preparing the Supabase client for sign-in.
const String kSignInNotReadyMessage = 'Clinic services are still starting. Wait a moment and try again.';

/// Shown when staff request a password reset from the login screen.
const String kForgotPasswordMessage = 'To reset your password, contact your clinic administrator.';

/// Shown when post-login session resolution exceeds [kPostLoginResolutionTimeout].
const String kPostLoginResolutionTimeoutMessage =
    'Sign-in is taking longer than expected. If this continues after a backend update, sign out, restart the app, and try again.';

/// Documented GoTrue code for invalid password sign-in (not present on [ErrorCode] enum).
const String _kInvalidCredentialsCode = 'invalid_credentials';

/// Maximum time to wait for [authSessionProvider] to settle after sign-in.
///
/// Replaces the former poll loop (`kPostLoginResolutionMaxAttempts` ×
/// `kPostLoginResolutionPollInterval`).
const Duration kPostLoginResolutionTimeout = Duration(seconds: 3);

@immutable
class AuthUiState {
  const AuthUiState({this.isSubmitting = false, this.errorMessage, this.isInfoMessage = false});

  final bool isSubmitting;
  final String? errorMessage;
  final bool isInfoMessage;

  AuthUiState copyWith({
    bool? isSubmitting,
    Object? errorMessage = copyWithSentinel,
    bool? isInfoMessage,
  }) {
    return AuthUiState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: identical(errorMessage, copyWithSentinel) ? this.errorMessage : errorMessage as String?,
      isInfoMessage: isInfoMessage ?? this.isInfoMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AuthUiState &&
        other.isSubmitting == isSubmitting &&
        other.errorMessage == errorMessage &&
        other.isInfoMessage == isInfoMessage;
  }

  @override
  int get hashCode => Object.hash(isSubmitting, errorMessage, isInfoMessage);
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthUiState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthUiState> {
  @override
  AuthUiState build() => const AuthUiState();

  bool validateCredentials({required String username, required String password}) {
    if (validateStaffUsername(username) != null) {
      return false;
    }

    return password.isNotEmpty;
  }

  Future<void> signIn({required String username, required String password}) async {
    if (!validateCredentials(username: username, password: password)) {
      final usernameError = validateStaffUsername(username);
      state = state.copyWith(errorMessage: usernameError ?? 'Password is required.');
      return;
    }

    state = state.copyWith(isSubmitting: true, errorMessage: null, isInfoMessage: false);

    try {
      await ref.read(authSessionProvider.notifier).ensureReadyForSignIn();
      await ref.read(authRepositoryProvider).signIn(username: username, password: password);
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
    if (_isInvalidCredentialsError(error)) {
      return 'invalid_credentials';
    }
    if (_isUnavailableAuthError(error)) {
      return 'unavailable';
    }
    return 'auth_error';
  }

  static String _unexpectedErrorCategory(Object error) {
    if (_isStaffProvisioningError(error)) {
      return 'missing_staff_permissions';
    }
    if (_isUnavailableInfrastructureError(error)) {
      return 'unavailable';
    }
    return 'unexpected';
  }

  static bool _isInvalidCredentialsError(AuthException error) {
    final code = error.code;
    if (code != null) {
      if (code == _kInvalidCredentialsCode || code == ErrorCode.userNotFound.code) {
        return true;
      }
      return false;
    }

    final message = error.message.toLowerCase();
    return message.contains('invalid login credentials') || message.contains('invalid_grant');
  }

  static bool _isUnavailableAuthError(AuthException error) {
    final code = error.code;
    if (code != null) {
      return const {
        ErrorCode.overRequestRateLimit,
        ErrorCode.overEmailSendRateLimit,
        ErrorCode.overSmsSendRateLimit,
        ErrorCode.requestTimeout,
        ErrorCode.hookTimeout,
        ErrorCode.hookTimeoutAfterRetry,
        ErrorCode.unexpectedFailure,
        ErrorCode.captchaFailed,
      }.any((value) => value.code == code);
    }

    if (error is AuthRetryableFetchException) {
      return true;
    }

    final details = '${error.statusCode ?? ''} ${error.message}'.toLowerCase();
    return details.contains('network') || details.contains('503') || details.contains('timeout');
  }

  static bool _isStaffProvisioningError(Object error) {
    final details = error.toString().toLowerCase();
    return details.contains('staff claims') || details.contains('staff profile');
  }

  static bool _isUnavailableInfrastructureError(Object error) {
    final details = error.toString().toLowerCase();
    return details.contains('postgrest') || details.contains('jwt') || details.contains('permission denied');
  }

  String _messageForUnexpectedSignInError(Object error) {
    if (_isStaffProvisioningError(error) || _isUnavailableInfrastructureError(error)) {
      return kSignInUnavailableMessage;
    }

    return kSignInUnavailableMessage;
  }

  String _messageForAuthException(AuthException error) {
    if (_isInvalidCredentialsError(error)) {
      return kGenericSignInFailureMessage;
    }

    return kSignInUnavailableMessage;
  }

  Future<void> _waitForPostLoginResolution() async {
    final completer = Completer<void>();
    late final ProviderSubscription<AuthSessionState> subscription;

    void onSessionUpdate(AuthSessionState session) {
      if (session.status == AuthSessionStatus.authenticated) {
        state = const AuthUiState();
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      if (session.status == AuthSessionStatus.unauthenticated && session.failureMessage != null) {
        state = state.copyWith(isSubmitting: false, errorMessage: session.failureMessage);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }

    subscription = ref.listen<AuthSessionState>(
      authSessionProvider,
      (_, next) => onSessionUpdate(next),
      fireImmediately: true,
    );

    try {
      await completer.future.timeout(kPostLoginResolutionTimeout);
    } on TimeoutException {
      await _handlePostLoginResolutionTimeout();
    } finally {
      subscription.close();
    }
  }

  Future<void> _handlePostLoginResolutionTimeout() async {
    final session = ref.read(authSessionProvider);
    if (session.status == AuthSessionStatus.authenticated) {
      state = const AuthUiState();
      return;
    }

    if (session.status == AuthSessionStatus.unauthenticated && session.failureMessage != null) {
      state = state.copyWith(isSubmitting: false, errorMessage: session.failureMessage);
      return;
    }

    AppLog.warning('auth.sign_in.failed category=post_login_timeout');
    await ref.read(authSessionProvider.notifier).signOut();
    state = state.copyWith(isSubmitting: false, errorMessage: kPostLoginResolutionTimeoutMessage);
  }

  /// Shows inline guidance when staff tap "Forgot your password?" on the login screen.
  void showForgotPasswordMessage() {
    state = state.copyWith(errorMessage: kForgotPasswordMessage, isInfoMessage: true);
  }

  /// Clears a displayed sign-in error without affecting an in-flight submission.
  void clearSignInError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(errorMessage: null, isInfoMessage: false);
  }

  /// Resets transient sign-in UI state when leaving the login screen.
  void resetSignInForm() {
    state = const AuthUiState();
  }

  /// Explicit sign-out (US4): clears Supabase session and in-memory permission cache.
  Future<void> signOut() async {
    await ref.read(authSessionProvider.notifier).signOut();
  }
}
