import 'dart:async';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart' as domain;
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';

class _SignInHarness {
  _SignInHarness({
    required this.container,
    required this.authNotifier,
    required this.repository,
    required this.sessionNotifier,
    required this.callOrder,
  });

  final ProviderContainer container;
  final AuthNotifier authNotifier;
  final _SignInAuthRepository repository;
  final _SignInSessionNotifier sessionNotifier;
  final List<String> callOrder;

  AuthUiState get uiState => container.read(authNotifierProvider);
}

_SignInHarness createSignInHarness({_SignInSessionNotifier? sessionNotifier}) {
  final callOrder = <String>[];
  final session = sessionNotifier ?? _SignInSessionNotifier(callOrder: callOrder);
  final repository = _SignInAuthRepository(callOrder: callOrder);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      authSessionProvider.overrideWith(() => session),
    ],
  );
  addTearDown(container.dispose);
  container.read(authSessionProvider);

  return _SignInHarness(
    container: container,
    authNotifier: container.read(authNotifierProvider.notifier),
    repository: repository,
    sessionNotifier: session,
    callOrder: callOrder,
  );
}

Future<void> expectCompletesNormally(Future<void> future) async {
  await expectLater(future, completes);
}

void main() {
  group('AuthNotifier signIn constants', () {
    test('public message constants are non-empty and mutually distinct', () {
      const messages = <String>[
        kGenericSignInFailureMessage,
        kSignInUnavailableMessage,
        kSignInNotReadyMessage,
        kForgotPasswordMessage,
        kPostLoginResolutionTimeoutMessage,
      ];

      for (final message in messages) {
        expect(message, isNotEmpty);
      }
      expect(messages.toSet().length, messages.length);
    });

    test('kPostLoginResolutionTimeout equals three seconds', () {
      expect(kPostLoginResolutionTimeout, const Duration(seconds: 3));
    });
  });

  group('AuthNotifier.signIn validation short-circuit', () {
    test('invalid username sets error without calling repository', () async {
      final harness = createSignInHarness();

      await harness.authNotifier.signIn(username: 'ab', password: 'secret');

      expect(harness.repository.signInCalls, 0);
      expect(harness.uiState.errorMessage, isNotNull);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    });

    // The validation branch of signIn sets errorMessage without resetting
    // isInfoMessage, so a validation failure that follows the forgot-password
    // banner is still flagged as informational. Pinned to catch a change either
    // way; the error path arguably should clear the flag.
    test('validation failure after forgot-password keeps the info flag set', () async {
      final harness = createSignInHarness();

      harness.authNotifier.showForgotPasswordMessage();
      expect(harness.uiState.isInfoMessage, isTrue);

      await harness.authNotifier.signIn(username: 'ab', password: 'secret');

      expect(harness.repository.signInCalls, 0);
      expect(harness.uiState.errorMessage, 'Enter a valid username.');
      expect(harness.uiState.isInfoMessage, isTrue);
    });

    test('successful submission clears a lingering info flag', () async {
      final harness = createSignInHarness();
      harness.sessionNotifier.authenticateOnSync = true;

      harness.authNotifier.showForgotPasswordMessage();
      await harness.authNotifier.signIn(username: 'staff1', password: 'secret');

      expect(harness.uiState.isInfoMessage, isFalse);
      expect(harness.uiState.errorMessage, isNull);
    });

    test('empty password sets required message without calling repository', () async {
      final harness = createSignInHarness();

      await harness.authNotifier.signIn(username: 'staff1', password: '');

      expect(harness.repository.signInCalls, 0);
      expect(harness.uiState.errorMessage, 'Password is required.');
      expect(harness.uiState.isSubmitting, isFalse);
    });
  });

  group('AuthNotifier.signIn happy path', () {
    test('submits, calls session and repository in order, then resets UI state', () async {
      final harness = createSignInHarness();
      harness.sessionNotifier.authenticateOnSync = true;

      final signInFuture = harness.authNotifier.signIn(username: '  Staff1  ', password: 'secret');

      expect(harness.uiState.isSubmitting, isTrue);
      expect(harness.uiState.errorMessage, isNull);
      expect(harness.uiState.isInfoMessage, isFalse);

      await signInFuture;

      expect(harness.callOrder, ['ensureReadyForSignIn', 'signIn', 'syncAfterSignIn']);
      expect(harness.repository.signInCalls, 1);
      expect(harness.repository.lastUsername, '  Staff1  ');
      expect(harness.repository.lastPassword, 'secret');
      expect(harness.uiState, const AuthUiState());
    });
  });

  group('AuthNotifier.signIn AuthException invalid credentials', () {
    Future<void> expectInvalidCredentialsMessage(AuthException error) async {
      final harness = createSignInHarness();
      harness.repository.signInError = error;

      await expectCompletesNormally(harness.authNotifier.signIn(username: 'staff1', password: 'secret'));

      expect(harness.uiState.errorMessage, kGenericSignInFailureMessage);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    }

    test('maps invalid_credentials code', () async {
      await expectInvalidCredentialsMessage(const AuthException('bad', code: 'invalid_credentials'));
    });

    test('maps user_not_found code', () async {
      await expectInvalidCredentialsMessage(AuthException('bad', code: ErrorCode.userNotFound.code));
    });

    test('maps invalid login credentials message without code', () async {
      await expectInvalidCredentialsMessage(const AuthException('Invalid login credentials'));
    });

    test('maps invalid_grant message without code', () async {
      await expectInvalidCredentialsMessage(const AuthException('OAuth invalid_grant'));
    });
  });

  group('AuthNotifier.signIn AuthException unavailable', () {
    Future<void> expectUnavailableMessage(AuthException error) async {
      final harness = createSignInHarness();
      harness.repository.signInError = error;

      await expectCompletesNormally(harness.authNotifier.signIn(username: 'staff1', password: 'secret'));

      expect(harness.uiState.errorMessage, kSignInUnavailableMessage);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    }

    test('maps over_request_rate_limit code', () async {
      await expectUnavailableMessage(AuthException('rate limited', code: ErrorCode.overRequestRateLimit.code));
    });

    test('maps over_email_send_rate_limit code', () async {
      await expectUnavailableMessage(AuthException('rate limited', code: ErrorCode.overEmailSendRateLimit.code));
    });

    test('maps over_sms_send_rate_limit code', () async {
      await expectUnavailableMessage(AuthException('rate limited', code: ErrorCode.overSmsSendRateLimit.code));
    });

    test('maps request_timeout code', () async {
      await expectUnavailableMessage(AuthException('timed out', code: ErrorCode.requestTimeout.code));
    });

    test('maps hook_timeout code', () async {
      await expectUnavailableMessage(AuthException('timed out', code: ErrorCode.hookTimeout.code));
    });

    test('maps hook_timeout_after_retry code', () async {
      await expectUnavailableMessage(AuthException('timed out', code: ErrorCode.hookTimeoutAfterRetry.code));
    });

    test('maps unexpected_failure code', () async {
      await expectUnavailableMessage(AuthException('failed', code: ErrorCode.unexpectedFailure.code));
    });

    test('maps captcha_failed code', () async {
      await expectUnavailableMessage(AuthException('captcha', code: ErrorCode.captchaFailed.code));
    });

    test('maps AuthRetryableFetchException', () async {
      await expectUnavailableMessage(AuthRetryableFetchException(message: 'network fetch failed'));
    });

    test('maps network details without code', () async {
      await expectUnavailableMessage(const AuthException('network connection lost'));
    });

    test('maps 503 details without code', () async {
      await expectUnavailableMessage(const AuthException('service unavailable', statusCode: '503'));
    });

    test('maps timeout details without code', () async {
      await expectUnavailableMessage(const AuthException('gateway timeout'));
    });
  });

  group('AuthNotifier.signIn other failures', () {
    test('maps StateError from ensureReadyForSignIn to not-ready message', () async {
      final harness = createSignInHarness();
      harness.sessionNotifier.ensureReadyError = StateError('Startup configuration is not ready for sign-in.');

      await expectCompletesNormally(harness.authNotifier.signIn(username: 'staff1', password: 'secret'));

      expect(harness.repository.signInCalls, 0);
      expect(harness.uiState.errorMessage, kSignInNotReadyMessage);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    });

    Future<void> expectUnexpectedUnavailable(Object error) async {
      final harness = createSignInHarness();
      harness.repository.signInError = error;

      await expectCompletesNormally(harness.authNotifier.signIn(username: 'staff1', password: 'secret'));

      expect(harness.uiState.errorMessage, kSignInUnavailableMessage);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    }

    test('maps staff claims provisioning errors', () async {
      await expectUnexpectedUnavailable(Exception('missing staff claims in JWT'));
    });

    test('maps staff profile provisioning errors', () async {
      await expectUnexpectedUnavailable(Exception('staff profile not found'));
    });

    test('maps PostgREST infrastructure errors', () async {
      await expectUnexpectedUnavailable(Exception('PostgREST connection failed'));
    });

    test('maps JWT infrastructure errors', () async {
      await expectUnexpectedUnavailable(Exception('jwt malformed'));
    });

    test('maps permission denied infrastructure errors', () async {
      await expectUnexpectedUnavailable(Exception('permission denied for table'));
    });

    test('maps arbitrary unexpected exceptions', () async {
      await expectUnexpectedUnavailable(Exception('boom'));
    });
  });

  group('AuthNotifier.signIn post-login resolution', () {
    test('surfaces session failureMessage verbatim when unauthenticated after sync', () async {
      const failureMessage = 'Could not load staff profile.';
      final harness = createSignInHarness();
      harness.sessionNotifier.failureMessageOnSync = failureMessage;

      await harness.authNotifier.signIn(username: 'staff1', password: 'secret');

      expect(harness.uiState.errorMessage, failureMessage);
      expect(harness.uiState.isSubmitting, isFalse);
      expect(harness.uiState.isInfoMessage, isFalse);
    });

    test('waits for timeout then signs out when session stays unauthenticated without failure', () {
      FakeAsync().run((async) {
        final harness = createSignInHarness();
        var completed = false;

        harness.authNotifier.signIn(username: 'staff1', password: 'secret').then((_) => completed = true);

        async.flushMicrotasks();
        expect(harness.uiState.isSubmitting, isTrue);

        async.elapse(kPostLoginResolutionTimeout);
        async.flushMicrotasks();

        expect(completed, isTrue);
        expect(harness.sessionNotifier.signOutCalls, 1);
        expect(harness.callOrder, contains('signOut'));
        expect(harness.uiState.errorMessage, kPostLoginResolutionTimeoutMessage);
        expect(harness.uiState.isSubmitting, isFalse);
        expect(harness.uiState.isInfoMessage, isFalse);
      });
    });
  });

  group('AuthNotifier.signIn concurrency', () {
    test('allows overlapping signIn calls without a guard', () async {
      final harness = createSignInHarness();
      final gate = Completer<void>();
      harness.repository.signInGate = gate;
      harness.sessionNotifier.authenticateOnSync = true;

      final first = harness.authNotifier.signIn(username: 'staff1', password: 'first');
      final second = harness.authNotifier.signIn(username: 'staff2', password: 'second');

      await Future<void>.delayed(Duration.zero);
      expect(harness.repository.signInCalls, 1);
      expect(harness.uiState.isSubmitting, isTrue);

      gate.complete();
      await Future.wait([first, second]);

      expect(harness.repository.signInCalls, 2);
      expect(harness.uiState, const AuthUiState());
    });
  });

  group('AuthNotifier forgot-password and form helpers', () {
    test('showForgotPasswordMessage sets info banner copy', () {
      final harness = createSignInHarness();

      harness.authNotifier.showForgotPasswordMessage();

      expect(harness.uiState.errorMessage, kForgotPasswordMessage);
      expect(harness.uiState.isInfoMessage, isTrue);
    });

    test('clearSignInError clears message and info flag', () {
      final harness = createSignInHarness();

      harness.authNotifier.showForgotPasswordMessage();
      harness.authNotifier.clearSignInError();

      expect(harness.uiState.errorMessage, isNull);
      expect(harness.uiState.isInfoMessage, isFalse);
    });

    test('clearSignInError is a no-op when there is no error', () {
      final harness = createSignInHarness();
      final before = harness.uiState;

      harness.authNotifier.clearSignInError();

      expect(harness.uiState, before);
    });

    test('resetSignInForm clears sign-in error state', () async {
      final harness = createSignInHarness();
      harness.repository.signInError = const AuthException('bad', code: 'invalid_credentials');
      await harness.authNotifier.signIn(username: 'staff1', password: 'secret');

      harness.authNotifier.resetSignInForm();

      expect(harness.uiState, const AuthUiState());
    });

    test('resetSignInForm clears info state', () {
      final harness = createSignInHarness();
      harness.authNotifier.showForgotPasswordMessage();

      harness.authNotifier.resetSignInForm();

      expect(harness.uiState, const AuthUiState());
    });

    test('resetSignInForm clears submitting state', () async {
      final harness = createSignInHarness();
      final gate = Completer<void>();
      harness.repository.signInGate = gate;

      final signInFuture = harness.authNotifier.signIn(username: 'staff1', password: 'secret');
      await Future<void>.delayed(Duration.zero);
      expect(harness.uiState.isSubmitting, isTrue);

      harness.authNotifier.resetSignInForm();
      expect(harness.uiState, const AuthUiState());

      gate.complete();
      await signInFuture;
    });
  });

  group('AuthNotifier.signOut', () {
    test('delegates to auth session notifier signOut', () async {
      final harness = createSignInHarness();

      await harness.authNotifier.signOut();

      expect(harness.sessionNotifier.signOutCalls, 1);
    });
  });
}

class _SignInSessionNotifier extends TestAuthSessionNotifier {
  _SignInSessionNotifier({required List<String> callOrder}) : _callOrder = callOrder;

  final List<String> _callOrder;
  Object? ensureReadyError;
  bool authenticateOnSync = false;
  String? failureMessageOnSync;
  int signOutCalls = 0;

  @override
  Future<void> ensureReadyForSignIn() async {
    _callOrder.add('ensureReadyForSignIn');
    if (ensureReadyError != null) {
      throw ensureReadyError!;
    }
  }

  @override
  Future<void> syncAfterSignIn() async {
    _callOrder.add('syncAfterSignIn');
    if (authenticateOnSync) {
      setAuthenticated();
      return;
    }
    if (failureMessageOnSync != null) {
      setUnauthenticated(failureMessage: failureMessageOnSync);
    }
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _callOrder.add('signOut');
    setUnauthenticated();
  }
}

class _SignInAuthRepository implements domain.AuthRepository {
  _SignInAuthRepository({required List<String> callOrder}) : _callOrder = callOrder;

  final List<String> _callOrder;
  int signInCalls = 0;
  String? lastUsername;
  String? lastPassword;
  Object? signInError;
  Completer<void>? signInGate;

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
    _callOrder.add('signIn');
    signInCalls++;
    lastUsername = username;
    lastPassword = password;
    if (signInGate != null) {
      await signInGate!.future;
    }
    if (signInError != null) {
      throw signInError!;
    }
  }

  @override
  Future<void> signOut() async {}
}
