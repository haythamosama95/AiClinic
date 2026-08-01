import 'dart:async';

import 'package:ai_clinic/core/config/in_memory_gotrue_async_storage.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/repositories/auth_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingSupabaseClient implements SupabaseClient {
  String? lastEmail;
  String? lastPassword;

  @override
  late final GoTrueClient auth = _RecordingGoTrue(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecordingGoTrue implements GoTrueClient {
  _RecordingGoTrue(this.client);

  final _RecordingSupabaseClient client;
  final _authStateController = StreamController<AuthState>.broadcast();

  int signOutCalls = 0;
  int refreshSessionCalls = 0;
  Session? session;
  User? user;
  AuthResponse? refreshSessionResult;
  AuthException? refreshSessionError;
  AuthException? signInError;

  @override
  Session? get currentSession => session;

  @override
  User? get currentUser => user;

  @override
  Stream<AuthState> get onAuthStateChange => _authStateController.stream;

  StreamController<AuthState> get authStateController => _authStateController;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
    session = null;
  }

  @override
  Future<AuthResponse> signInWithPassword({
    String? email,
    String? phone,
    required String password,
    String? captchaToken,
  }) async {
    if (signInError != null) {
      throw signInError!;
    }
    client.lastEmail = email;
    client.lastPassword = password;
    return AuthResponse();
  }

  @override
<<<<<<< HEAD
  Future<AuthResponse> refreshSession() async {
=======
  Future<AuthResponse> refreshSession([String? refreshToken]) async {
>>>>>>> master
    refreshSessionCalls++;
    if (refreshSessionError != null) {
      throw refreshSessionError!;
    }
    return refreshSessionResult ?? AuthResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ThrowingSignOutClient implements SupabaseClient {
  @override
  late final GoTrueClient auth = _ThrowingGoTrue();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ThrowingGoTrue implements GoTrueClient {
  Session? session;

  @override
  Session? get currentSession => session;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    throw const AuthException('No session');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _InvalidStartupNotifier extends StartupSessionNotifier {
  @override
  StartupSessionState build() {
    return const StartupSessionState(
      configurationStatus: StartupConfigurationStatus.invalid,
      connectivityStatus: StartupConnectivityStatus.unknown,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.system,
    );
  }
}

Session _testSession({String userId = 'user-1'}) {
  return Session(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
  );
}

void main() {
  group('InMemoryGotrueAsyncStorage', () {
    test('isolated instances do not share PKCE entries', () async {
      final first = InMemoryGotrueAsyncStorage.isolated();
      final second = InMemoryGotrueAsyncStorage.isolated();

      await first.setItem(key: 'pkce', value: 'verifier-a');
      expect(await second.getItem(key: 'pkce'), isNull);
    });

    test('reset clears stored PKCE entries', () async {
      final storage = InMemoryGotrueAsyncStorage.isolated();
      await storage.setItem(key: 'pkce', value: 'verifier');

      storage.reset();

      expect(await storage.getItem(key: 'pkce'), isNull);
    });
  });

  test('clearPersistedSessionOnColdStart invokes signOut when session exists', () async {
    final client = _RecordingSupabaseClient();
    final goTrue = client.auth as _RecordingGoTrue;
    goTrue.session = _testSession();
    final repository = AuthRepositoryImpl(client);

    await repository.clearPersistedSessionOnColdStart();

    expect(goTrue.signOutCalls, 1);
  });

  test('clearPersistedSessionOnColdStart skips signOut when session is null', () async {
    final client = _RecordingSupabaseClient();
    final repository = AuthRepositoryImpl(client);

    await repository.clearPersistedSessionOnColdStart();

    expect((client.auth as _RecordingGoTrue).signOutCalls, 0);
  });

  test('clearPersistedSessionOnColdStart swallows AuthException', () async {
    final client = _ThrowingSignOutClient();
    final goTrue = client.auth as _ThrowingGoTrue;
    goTrue.session = _testSession();
    final repository = AuthRepositoryImpl(client);

    await expectLater(repository.clearPersistedSessionOnColdStart(), completes);
  });

  group('signOut', () {
    test('clears injected PKCE storage', () async {
      final client = _RecordingSupabaseClient();
      final pkceStorage = InMemoryGotrueAsyncStorage.isolated();
      await pkceStorage.setItem(key: 'pkce', value: 'verifier');
      final repository = AuthRepositoryImpl(client, pkceStorage: pkceStorage);

      await repository.signOut();

      expect(await pkceStorage.getItem(key: 'pkce'), isNull);
    });

    test('does not clear PKCE storage when underlying signOut throws', () async {
      final client = _ThrowingSignOutClient();
      final pkceStorage = InMemoryGotrueAsyncStorage.isolated();
      await pkceStorage.setItem(key: 'pkce', value: 'verifier');
      final repository = AuthRepositoryImpl(client, pkceStorage: pkceStorage);

      await expectLater(repository.signOut(), throwsA(isA<AuthException>()));
      expect(await pkceStorage.getItem(key: 'pkce'), 'verifier');
    });

    test('propagates errors from underlying client', () async {
      final client = _ThrowingSignOutClient();
      final repository = AuthRepositoryImpl(client);

      await expectLater(
        repository.signOut(),
        throwsA(
          predicate<AuthException>((error) => error.message == 'No session'),
        ),
      );
    });

    test('succeeds with default PKCE storage when pkceStorage is omitted', () async {
      final client = _RecordingSupabaseClient();
      final repository = AuthRepositoryImpl(client);

      await expectLater(repository.signOut(), completes);
      expect((client.auth as _RecordingGoTrue).signOutCalls, 1);
    });
  });

  group('signIn', () {
    test('normalizes username before calling auth client', () async {
      final client = _RecordingSupabaseClient();
      final repository = AuthRepositoryImpl(client);

      await repository.signIn(username: '  Staff1  ', password: 'secret');

      expect(client.lastEmail, 'staff1');
    });

    test('passes password verbatim while normalizing username', () async {
      final client = _RecordingSupabaseClient();
      final repository = AuthRepositoryImpl(client);

      await repository.signIn(username: '  ADMIN  ', password: '  SeCrEt  ');

      expect(client.lastEmail, 'admin');
      expect(client.lastPassword, '  SeCrEt  ');
    });

    test('normalizes padded uppercase username to lowercase', () async {
      final client = _RecordingSupabaseClient();
      final repository = AuthRepositoryImpl(client);

      await repository.signIn(username: '  ADMIN  ', password: 'pass');

      expect(client.lastEmail, 'admin');
    });

    test('propagates AuthException from underlying client unchanged', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      const error = AuthException('Invalid login credentials', statusCode: '400');
      goTrue.signInError = error;
      final repository = AuthRepositoryImpl(client);

      await expectLater(
        repository.signIn(username: 'admin', password: 'wrong'),
        throwsA(same(error)),
      );
    });
  });

  group('refreshSession', () {
    test('completes when underlying client returns a non-null session', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      goTrue.refreshSessionResult = AuthResponse(session: _testSession());
      final repository = AuthRepositoryImpl(client);

      await expectLater(repository.refreshSession(), completes);

      expect(goTrue.refreshSessionCalls, 1);
    });

    test('throws AuthException when response session is null', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      goTrue.refreshSessionResult = AuthResponse();
      final repository = AuthRepositoryImpl(client);

      await expectLater(
        repository.refreshSession(),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            'Session refresh failed.',
          ),
        ),
      );
    });

    test('propagates AuthException from underlying client', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      const error = AuthException('Token revoked');
      goTrue.refreshSessionError = error;
      final repository = AuthRepositoryImpl(client);

      await expectLater(repository.refreshSession(), throwsA(same(error)));
    });
  });

  group('authStateChanges', () {
    test('returns underlying onAuthStateChange stream without transformation', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      final repository = AuthRepositoryImpl(client);

<<<<<<< HEAD
      expect(repository.authStateChanges, same(goTrue.onAuthStateChange));

=======
>>>>>>> master
      final events = <AuthState>[];
      final subscription = repository.authStateChanges.listen(events.add);

      final first = AuthState(AuthChangeEvent.signedIn, _testSession());
      final second = AuthState(AuthChangeEvent.tokenRefreshed, _testSession(userId: 'user-2'));
      goTrue.authStateController.add(first);
      goTrue.authStateController.add(second);
      await Future<void>.delayed(Duration.zero);

      expect(events, [first, second]);
      await subscription.cancel();
    });

    test('surfaces stream errors to listeners', () async {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      final repository = AuthRepositoryImpl(client);
      final errors = <Object>[];
      final subscription = repository.authStateChanges.listen(
        (_) {},
        onError: errors.add,
      );

      final error = StateError('auth stream failed');
      goTrue.authStateController.addError(error);
      await Future<void>.delayed(Duration.zero);

      expect(errors, [error]);
      await subscription.cancel();
    });
  });

  group('session passthrough', () {
    test('currentSession returns underlying session including null', () {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      final repository = AuthRepositoryImpl(client);

      expect(repository.currentSession, isNull);

      final session = _testSession();
      goTrue.session = session;
      expect(repository.currentSession, same(session));
    });

    test('currentUser returns underlying user including null', () {
      final client = _RecordingSupabaseClient();
      final goTrue = client.auth as _RecordingGoTrue;
      final repository = AuthRepositoryImpl(client);

      expect(repository.currentUser, isNull);

      final user = _testSession().user;
      goTrue.user = user;
      expect(repository.currentUser, same(user));
    });
  });

  test('AuthRepositoryImpl satisfies AuthRepository interface', () {
    AuthRepository repository = AuthRepositoryImpl(_RecordingSupabaseClient());
    expect(repository, isA<AuthRepository>());
  });

  test('authRepositoryProvider returns cached AuthRepositoryImpl', () {
    final client = _RecordingSupabaseClient();
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    final first = container.read(authRepositoryProvider);
    final second = container.read(authRepositoryProvider);

    expect(first, isA<AuthRepository>());
    expect(first, isA<AuthRepositoryImpl>());
    expect(identical(first, second), isTrue);
  });

  test('supabaseClientProvider throws when bootstrap not ready', () {
    SupabaseBootstrap.debugResetForTests();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      () => container.read(supabaseClientProvider),
      throwsA(
        predicate<Object>((error) {
          return error is StateError || error.toString().contains('Supabase has not been initialized');
        }),
      ),
    );
  });

  test('ensureReadyForSignIn throws when startup configuration is invalid', () async {
    final container = ProviderContainer(
      overrides: [
        startupSessionProvider.overrideWith(_InvalidStartupNotifier.new),
        authSessionProvider.overrideWith(AuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(authSessionProvider.notifier).ensureReadyForSignIn(),
      throwsA(predicate<Object>((error) => error is StateError && error.toString().contains('not ready'))),
    );
  });
}
