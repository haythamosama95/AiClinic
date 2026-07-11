import 'package:ai_clinic/core/config/in_memory_gotrue_async_storage.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingSupabaseClient implements SupabaseClient {
  String? lastEmail;

  @override
  late final GoTrueClient auth = _RecordingGoTrue(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecordingGoTrue implements GoTrueClient {
  _RecordingGoTrue(this.client);

  final _RecordingSupabaseClient client;
  int signOutCalls = 0;
  Session? session;

  @override
  Session? get currentSession => session;

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
    client.lastEmail = email;
    return AuthResponse();
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
    goTrue.session = Session(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'bearer',
      user: User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );
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
    goTrue.session = Session(
      accessToken: 'access',
      refreshToken: 'refresh',
      tokenType: 'bearer',
      user: User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );
    final repository = AuthRepositoryImpl(client);

    await expectLater(repository.clearPersistedSessionOnColdStart(), completes);
  });

  test('signOut clears injected PKCE storage', () async {
    final client = _RecordingSupabaseClient();
    final pkceStorage = InMemoryGotrueAsyncStorage.isolated();
    await pkceStorage.setItem(key: 'pkce', value: 'verifier');
    final repository = AuthRepositoryImpl(client, pkceStorage: pkceStorage);

    await repository.signOut();

    expect(await pkceStorage.getItem(key: 'pkce'), isNull);
  });

  test('signIn normalizes username before calling auth client', () async {
    final client = _RecordingSupabaseClient();
    final repository = AuthRepositoryImpl(client);

    await repository.signIn(username: '  Staff1  ', password: 'secret');

    expect(client.lastEmail, 'staff1');
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
