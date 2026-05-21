import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RecordingSupabaseClient implements SupabaseClient {
  String? lastEmail;

  late final GoTrueClient auth = _RecordingGoTrue(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _RecordingGoTrue implements GoTrueClient {
  _RecordingGoTrue(this.client);

  final _RecordingSupabaseClient client;
  int signOutCalls = 0;

  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.local}) async {
    signOutCalls++;
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
  late final GoTrueClient auth = _ThrowingGoTrue();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ThrowingGoTrue implements GoTrueClient {
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
  test('clearPersistedSessionOnColdStart invokes signOut', () async {
    final client = _RecordingSupabaseClient();
    final repository = AuthRepository(client);

    await repository.clearPersistedSessionOnColdStart();

    expect((client.auth as _RecordingGoTrue).signOutCalls, 1);
  });

  test('clearPersistedSessionOnColdStart swallows AuthException', () async {
    final client = _ThrowingSignOutClient();
    final repository = AuthRepository(client);

    await expectLater(repository.clearPersistedSessionOnColdStart(), completes);
  });

  test('signIn trims email before calling auth client', () async {
    final client = _RecordingSupabaseClient();
    final repository = AuthRepository(client);

    await repository.signIn(email: '  staff@clinic.test  ', password: 'secret');

    expect(client.lastEmail, 'staff@clinic.test');
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
