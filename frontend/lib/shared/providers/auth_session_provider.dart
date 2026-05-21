import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';

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

class AuthSessionNotifier extends Notifier<AuthSessionState> {
  StreamSubscription<AuthState>? _authSubscription;

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

  Future<void> _ensureSupabaseReady(StartupSessionState startup) async {
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

      await _bindAuthListener();

      if (state.status == AuthSessionStatus.unknown || state.status == AuthSessionStatus.loading) {
        await _syncFromCurrentSession();
      }
    } catch (error) {
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
      state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
      return;
    }

    state = state.copyWith(status: AuthSessionStatus.loading, clearFailure: true);
    try {
      final context = await _loadSessionContext(authState.session!);
      state = AuthSessionState(status: AuthSessionStatus.authenticated, context: context);
      AppLog.fine(
        'auth.session.authenticated role=${context.staffProfile.role.wireValue} '
        'setup=${context.setupRequired}',
      );
    } catch (error) {
      AppLog.warning('auth.session.context_failed reason=${_contextFailureReason(error)}');
      await ref.read(authRepositoryProvider).signOut();
      state = AuthSessionState(status: AuthSessionStatus.unauthenticated, failureMessage: error.toString());
    }
  }

  static String _contextFailureReason(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('missing staff claims')) {
      if (message.contains('staff_role') || message.contains('staff claims')) {
        return 'missing_staff_claims';
      }
      return 'missing_staff_claims';
    }
    if (message.contains('inactive')) {
      return 'inactive_staff';
    }
    if (message.contains('no active staff profile')) {
      return 'staff_profile_missing';
    }
    return error.runtimeType.toString();
  }

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

  Future<AuthSessionContext> _loadSessionContext(Session session) async {
    final claims = decodeAccessTokenClaims(session.accessToken);
    final staffMemberId = claims['staff_member_id']?.toString();
    final role = StaffRole.tryParse(claims['staff_role']?.toString());

    if (staffMemberId == null || role == null) {
      throw StateError('Authenticated session is missing staff claims.');
    }

    final client = ref.read(supabaseClientProvider);
    final staffRow = await client
        .from('staff_members')
        .select('id, full_name, role, is_bootstrap_admin, is_active')
        .eq('id', staffMemberId)
        .maybeSingle();

    if (staffRow == null) {
      throw StateError('No active staff profile is linked to this account.');
    }

    if (staffRow['is_active'] != true) {
      throw StateError('This staff account is inactive. Contact your clinic administrator.');
    }

    final branchIdsRaw = claims['branch_ids']?.toString() ?? '';
    final branchIds = branchIdsRaw.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toList();

    final permissions = await _loadPermissions(role);
    final primaryBranchId = branchIds.isEmpty ? null : branchIds.first;
    final setupRequired = claims['setup_required'] == true || claims['setup_required']?.toString() == 'true';

    return AuthSessionContext(
      staffProfile: StaffProfile(
        staffMemberId: staffMemberId,
        fullName: staffRow['full_name']?.toString() ?? 'Staff',
        role: role,
        isBootstrapAdmin: staffRow['is_bootstrap_admin'] == true,
        isActive: staffRow['is_active'] == true,
      ),
      organizationId: claims['organization_id']?.toString(),
      branchIds: branchIds,
      activeBranchId: primaryBranchId,
      permissions: permissions,
      setupRequired: setupRequired,
    );
  }

  Future<Set<String>> _loadPermissions(StaffRole role) async {
    final client = ref.read(supabaseClientProvider);
    final rows = await client
        .from('roles_permissions')
        .select('permission_key')
        .eq('role', role.wireValue)
        .eq('is_granted', true);

    final permissions = <String>{};
    for (final row in rows) {
      final key = row['permission_key']?.toString();
      if (key != null && key.isNotEmpty) {
        permissions.add(key);
      }
    }
    return permissions;
  }

  void setActiveBranch(String branchId) {
    final context = state.context;
    if (context == null || !context.branchIds.contains(branchId)) {
      return;
    }
    state = state.copyWith(context: context.copyWith(activeBranchId: branchId));
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthSessionState(status: AuthSessionStatus.unauthenticated);
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
