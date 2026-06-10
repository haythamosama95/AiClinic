import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/session_context_loader.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';

/// High-level auth lifecycle used by routing and permission services.
enum AuthSessionStatus { unknown, unauthenticated, loading, authenticated }

class AuthSessionState {
  const AuthSessionState({required this.status, this.context, this.failureMessage});

  factory AuthSessionState.initial() => const AuthSessionState(status: AuthSessionStatus.unknown);

  final AuthSessionStatus status;
  final AuthSessionContext? context;
  final String? failureMessage;

  bool get isAuthenticated => status == AuthSessionStatus.authenticated && context != null;

  AuthSessionState copyWith({
    AuthSessionStatus? status,
    AuthSessionContext? context,
    String? failureMessage,
    bool clearContext = false,
    bool clearFailure = false,
  }) {
    return AuthSessionState(
      status: status ?? this.status,
      context: clearContext ? null : (context ?? this.context),
      failureMessage: clearFailure ? null : (failureMessage ?? this.failureMessage),
    );
  }
}

final authSessionProvider = NotifierProvider<AuthSessionNotifier, AuthSessionState>(AuthSessionNotifier.new);

final idleTimeoutServiceProvider = Provider<IdleTimeoutService>((ref) {
  late final IdleTimeoutService service;
  service = IdleTimeoutService(
    onIdleTimeout: () {
      unawaited(ref.read(authSessionProvider.notifier).signOutDueToInactivity());
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

class AuthSessionNotifier extends Notifier<AuthSessionState> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _intentionalSignOut = false;
  Future<void>? _ensureSupabaseReadyTask;
  bool _clearedPersistedSessionOnColdStart = false;

  @override
  AuthSessionState build() {
    ref.onDispose(() {
      unawaited(_authSubscription?.cancel());
    });

    ref.listen<StartupSessionState>(startupSessionProvider, (previous, next) {
      if (next.configurationStatus == StartupConfigurationStatus.valid && next.deploymentProfile != null) {
        unawaited(_ensureSupabaseReady(next));
      }
    });

    final startup = ref.read(startupSessionProvider);
    if (startup.configurationStatus == StartupConfigurationStatus.valid && startup.deploymentProfile != null) {
      Future<void>.microtask(() => _ensureSupabaseReady(startup));
    }

    return AuthSessionState.initial();
  }

  Future<void> _ensureSupabaseReady(StartupSessionState startup) {
    return _ensureSupabaseReadyTask ??= _runEnsureSupabaseReady(startup);
  }

  Future<void> _runEnsureSupabaseReady(StartupSessionState startup) async {
    final profile = startup.deploymentProfile;
    if (profile == null) {
      return;
    }

    try {
      if (!SupabaseBootstrap.isReady) {
        state = state.copyWith(status: AuthSessionStatus.loading, clearFailure: true);
        await SupabaseBootstrap.ensureInitialized(SupabaseConfig.fromDeploymentProfile(profile));
      }

      if (!SupabaseBootstrap.isReady) {
        return;
      }

      // Run once per process. Concurrent bootstrap + sign-in used to call signOut again
      // after password sign-in and break the first PostgREST request (PGRST301).
      if (!_clearedPersistedSessionOnColdStart) {
        await ref.read(authRepositoryProvider).clearPersistedSessionOnColdStart();
        _clearedPersistedSessionOnColdStart = true;
      }

      await _bindAuthListener();

      if (state.status == AuthSessionStatus.unknown || state.status == AuthSessionStatus.loading) {
        await _syncFromCurrentSession();
      }
    } catch (error) {
      _ensureSupabaseReadyTask = null;
      AppLog.warning('auth.session.bootstrap_failed reason=${error.runtimeType}');
      state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: error.toString());
    }
  }

  Future<void> _bindAuthListener() async {
    if (_authSubscription != null) {
      return;
    }

    final repository = ref.read(authRepositoryProvider);
    _authSubscription = repository.authStateChanges.listen((authState) {
      unawaited(_handleAuthState(authState));
    });
  }

  Future<void> _handleAuthState(AuthState authState) async {
    if (authState.event == AuthChangeEvent.signedOut || authState.session == null) {
      _setUnauthenticatedAfterExternalSignOut();
      return;
    }

    if (authState.event == AuthChangeEvent.tokenRefreshed && authState.session != null) {
      if (state.isAuthenticated) {
        try {
          final context = await _loadSessionContext(authState.session!);
          state = AuthSessionState(status: AuthSessionStatus.authenticated, context: context);
        } catch (error) {
          AppLog.warning('auth.session.token_refresh_context_failed reason=${_contextFailureReason(error)}');
          await ref.read(authRepositoryProvider).signOut();
          state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: kSessionEndedMessage);
          _syncIdleMonitoring();
        }
      }
      return;
    }

    state = state.copyWith(status: AuthSessionStatus.loading, clearFailure: true);
    try {
      final context = await _loadSessionContext(authState.session!);
      state = AuthSessionState(status: AuthSessionStatus.authenticated, context: context);
      _syncIdleMonitoring();
      AppLog.fine(
        'auth.session.authenticated role=${context.staffProfile.role.wireValue} '
        'setup=${context.setupRequired}',
      );
    } catch (error) {
      AppLog.warning('auth.session.context_failed reason=${_contextFailureReason(error)}');
      await ref.read(authRepositoryProvider).signOut();
      state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: error.toString());
      _syncIdleMonitoring();
    }
  }

  void _setUnauthenticatedAfterExternalSignOut() {
    final wasAuthenticated = state.isAuthenticated;
    final failureMessage = _intentionalSignOut || !wasAuthenticated ? null : kSessionEndedMessage;
    state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: failureMessage);
    _syncIdleMonitoring();
  }

  void _syncIdleMonitoring() {
    final idle = ref.read(idleTimeoutServiceProvider);
    if (state.isAuthenticated) {
      idle.enable(resetTimer: true);
      return;
    }
    idle.disable();
  }

  static String _contextFailureReason(Object error) => SessionContextLoader.contextFailureReason(error);

  Future<void> _syncFromCurrentSession() async {
    if (!SupabaseBootstrap.isReady) {
      state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
      return;
    }

    final session = ref.read(authRepositoryProvider).currentSession;
    if (session == null) {
      state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
      return;
    }

    await _handleAuthState(AuthState(AuthChangeEvent.initialSession, session));
  }

  SessionContextLoader get _contextLoader =>
      SessionContextLoader(ref.read(supabaseClientProvider), ref.read(permissionRepositoryProvider));

  Future<AuthSessionContext> _loadSessionContext(Session session) => _contextLoader.load(session);

  void setActiveBranch(String branchId) {
    final context = state.context;
    if (context == null || !context.branchIds.contains(branchId)) {
      return;
    }
    state = state.copyWith(context: context.copyWith(activeBranchId: branchId));
  }

  /// Clears a sign-in failure banner without changing auth status.
  void clearSignInFailureMessage() {
    if (state.failureMessage == null) return;
    state = state.copyWith(clearFailure: true);
  }

  Future<void> signOut() async {
    _intentionalSignOut = true;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      _intentionalSignOut = false;
    }
    state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
    _syncIdleMonitoring();
  }

  /// Automatic sign-out after idle timeout (FR-005a); does not use [signOut] message semantics.
  Future<void> signOutDueToInactivity() async {
    if (!state.isAuthenticated) {
      return;
    }

    _intentionalSignOut = true;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      _intentionalSignOut = false;
    }
    state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: kIdleTimeoutSignOutMessage);
    _syncIdleMonitoring();
  }

  /// Loads session context immediately after password sign-in (avoids missing auth stream events).
  Future<void> syncAfterSignIn() async {
    await _bindAuthListener();
    final session = ref.read(authRepositoryProvider).currentSession;
    if (session == null) {
      return;
    }

    await _handleAuthState(AuthState(AuthChangeEvent.signedIn, session));
  }

  /// Reloads staff profile and permission cache (FR-011; after matrix save or app resume).
  Future<void> reloadContext() => refreshSessionContext();

  /// Reloads session context after bootstrap RPCs change organization/branch claims.
  Future<void> refreshSessionContext() async {
    await ref.read(authRepositoryProvider).refreshSession();
    final session = ref.read(authRepositoryProvider).currentSession;
    if (session == null) {
      state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
      return;
    }

    // Keep [isAuthenticated] true during refresh so route guards do not redirect
    // away from deep-linked settings pages (e.g. role permissions matrix).
    try {
      final context = await _loadSessionContext(session);
      state = AuthSessionState(status: AuthSessionStatus.authenticated, context: context);
      _syncIdleMonitoring();
    } catch (error) {
      AppLog.warning('auth.session.refresh_failed reason=${_contextFailureReason(error)}');
      await ref.read(authRepositoryProvider).signOut();
      state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: kSessionEndedMessage);
      _syncIdleMonitoring();
    }
  }

  /// Waits until startup config is loaded and the Supabase client is ready for password sign-in.
  Future<void> ensureReadyForSignIn() async {
    final startup = ref.read(startupSessionProvider);
    if (startup.configurationStatus != StartupConfigurationStatus.valid || startup.deploymentProfile == null) {
      throw StateError('Startup configuration is not ready for sign-in.');
    }

    await _ensureSupabaseReady(startup);
    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase client is not initialized.');
    }
  }
}

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(ref.watch(authSessionProvider).context);
});
