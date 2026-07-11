import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/startup_test_support.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final claims = Map<String, dynamic>.from(payload);
  claims.putIfAbsent(
    'exp',
    () => DateTime.now().toUtc().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
  );
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$body.signature';
}

Session _fakeSession() {
  return Session(
    accessToken: _fakeJwt({
      'staff_member_id': '00000000-0000-4000-8000-000000000010',
      'staff_role': 'administrator',
      'organization_id': '00000000-0000-4000-8000-000000000020',
      'branch_ids': '00000000-0000-4000-8000-000000000001',
      'setup_required': false,
    }),
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    expiresIn: 3600,
    user: User(
      id: '00000000-0000-4000-8000-000000000099',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    ),
  );
}

void main() {
  test('session context uses staff_members.role when JWT staff_role differs', () async {
    final session = Session(
      accessToken: _fakeJwt({
        'staff_member_id': '00000000-0000-4000-8000-000000000010',
        'staff_role': 'doctor',
        'organization_id': '00000000-0000-4000-8000-000000000020',
        'branch_ids': '00000000-0000-4000-8000-000000000001',
        'setup_required': false,
      }),
      refreshToken: 'refresh-token',
      tokenType: 'bearer',
      expiresIn: 3600,
      user: User(
        id: '00000000-0000-4000-8000-000000000099',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );
    final supabaseClient = _AuthSessionTableTestClient({
      'staff_members': [
        {
          'id': '00000000-0000-4000-8000-000000000010',
          'full_name': 'DB Role Admin',
          'role': 'administrator',
          'is_bootstrap_admin': false,
          'is_active': true,
        },
      ],
    });

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => _ReloadAuthRepository(session: session, onRefresh: () {})),
        permissionRepositoryProvider.overrideWith(
          (ref) => _ReloadPermissionRepository(onLoad: () async => {'patients.view'}),
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_ReloadHarnessNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _ReloadHarnessNotifier;
    await notifier.refreshSessionContext();

    expect(notifier.state.context?.staffProfile.role, StaffRole.administrator);
  });

  test('reloadContext refreshes session and reloads permission grants', () async {
    var permissionLoads = 0;
    var refreshCalls = 0;
    final session = _fakeSession();
    final supabaseClient = _AuthSessionTableTestClient({
      'staff_members': [
        {
          'id': '00000000-0000-4000-8000-000000000010',
          'full_name': 'Reload Test',
          'role': 'administrator',
          'is_bootstrap_admin': false,
          'is_active': true,
        },
      ],
    });

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith(
          (ref) => _ReloadAuthRepository(session: session, onRefresh: () => refreshCalls++),
        ),
        permissionRepositoryProvider.overrideWith(
          (ref) => _ReloadPermissionRepository(
            onLoad: () async {
              permissionLoads++;
              return {'patients.view', 'settings.manage_branches'};
            },
          ),
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_ReloadHarnessNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _ReloadHarnessNotifier;
    notifier.state = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: AuthSessionContext(
        staffProfile: const StaffProfile(
          staffMemberId: '00000000-0000-4000-8000-000000000010',
          fullName: 'Reload Test',
          role: StaffRole.administrator,
          isBootstrapAdmin: false,
          isActive: true,
        ),
        organizationId: '00000000-0000-4000-8000-000000000020',
        branchIds: const ['00000000-0000-4000-8000-000000000001'],
        activeBranchId: '00000000-0000-4000-8000-000000000001',
        permissions: const {'patients.view'},
        setupRequired: false,
      ),
    );

    final statusesDuringReload = <AuthSessionStatus>[];
    final removeListener = container.listen(authSessionProvider, (_, next) {
      statusesDuringReload.add(next.status);
    });

    await notifier.reloadContext();
    removeListener.close();

    expect(refreshCalls, 1);
    expect(permissionLoads, 1);
    expect(statusesDuringReload, isNot(contains(AuthSessionStatus.loading)));
    final context = container.read(authSessionProvider).context;
    expect(context?.permissions, contains('settings.manage_branches'));
    expect(container.read(authSessionProvider).status, AuthSessionStatus.authenticated);
  });

  test('syncAfterSignIn joins duplicate in-flight context loads', () async {
    final permissionGate = Completer<void>();
    var permissionLoads = 0;
    final session = _fakeSession();
    final supabaseClient = _AuthSessionTableTestClient({
      'staff_members': [
        {
          'id': '00000000-0000-4000-8000-000000000010',
          'full_name': 'Join Test',
          'role': 'administrator',
          'is_bootstrap_admin': false,
          'is_active': true,
        },
      ],
    });

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => _ReloadAuthRepository(session: session, onRefresh: () {})),
        permissionRepositoryProvider.overrideWith(
          (ref) => _GatedPermissionRepository(
            onLoad: () async {
              permissionLoads++;
              await permissionGate.future;
              return {'patients.view'};
            },
          ),
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_ReloadHarnessNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _ReloadHarnessNotifier;
    final loads = Future.wait([notifier.syncAfterSignIn(), notifier.syncAfterSignIn()]);

    for (var attempt = 0; permissionLoads == 0 && attempt < 100; attempt++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(permissionLoads, 1);

    permissionGate.complete();
    await loads;

    expect(container.read(authSessionProvider).isAuthenticated, isTrue);
  });

  test('session context loading timeout transitions to unauthenticated', () async {
    final session = _fakeSession();
    final supabaseClient = _AuthSessionTableTestClient({
      'staff_members': [
        {
          'id': '00000000-0000-4000-8000-000000000010',
          'full_name': 'Timeout Test',
          'role': 'administrator',
          'is_bootstrap_admin': false,
          'is_active': true,
        },
      ],
    });

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => _ReloadAuthRepository(session: session, onRefresh: () {})),
        permissionRepositoryProvider.overrideWith(
          (ref) => _GatedPermissionRepository(onLoad: () => Completer<Set<String>>().future),
        ),
        supabaseClientProvider.overrideWithValue(supabaseClient),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(_ReloadHarnessNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authSessionProvider.notifier) as _ReloadHarnessNotifier;
    await notifier.syncAfterSignIn();

    expect(container.read(authSessionProvider).isAuthenticated, isFalse);
    expect(container.read(authSessionProvider).failureMessage, kSessionContextLoadingTimeoutMessage);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('cold start skips clearPersistedSessionOnColdStart when no session exists', () async {
    SupabaseBootstrap.debugMarkReadyForTests();
    addTearDown(SupabaseBootstrap.debugResetForTests);

    var clearCalls = 0;
    final container = ProviderContainer(
      overrides: [
        startupSessionProvider.overrideWith(_ValidStartupNotifier.new),
        authRepositoryProvider.overrideWith(
          (ref) => _ColdStartAuthRepository(onClear: () => clearCalls++),
        ),
        supabaseClientProvider.overrideWithValue(_ReloadFakeClient()),
        idleTimeoutServiceProvider.overrideWith((ref) {
          final idle = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () {});
          ref.onDispose(idle.dispose);
          return idle;
        }),
        authSessionProvider.overrideWith(AuthSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authSessionProvider.notifier).ensureReadyForSignIn();

    expect(clearCalls, 0);
    expect(container.read(authSessionProvider).status, AuthSessionStatus.unauthenticated);
  });
}

class _ReloadHarnessNotifier extends AuthSessionNotifier {
  @override
  AuthSessionState build() => const AuthSessionState(status: AuthSessionStatus.unauthenticated);
}

class _ReloadAuthRepository extends AuthRepositoryImpl {
  _ReloadAuthRepository({required this.session, required void Function() onRefresh})
    : _onRefresh = onRefresh,
      super(_ReloadFakeClient());

  final Session session;
  final void Function() _onRefresh;

  @override
  Session? get currentSession => session;

  @override
  Future<void> refreshSession() async {
    _onRefresh();
  }

  @override
  Future<void> signOut() async {}

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

class _ReloadPermissionRepository extends PermissionRepositoryImpl {
  _ReloadPermissionRepository({required Future<Set<String>> Function() onLoad})
    : _onLoad = onLoad,
      super(_ReloadFakeClient());

  final Future<Set<String>> Function() _onLoad;

  @override
  Future<Set<String>> loadGrantedPermissions(StaffRole role) => _onLoad();
}

class _GatedPermissionRepository extends PermissionRepositoryImpl {
  _GatedPermissionRepository({required Future<Set<String>> Function() onLoad})
    : _onLoad = onLoad,
      super(_ReloadFakeClient());

  final Future<Set<String>> Function() _onLoad;

  @override
  Future<Set<String>> loadGrantedPermissions(StaffRole role) => _onLoad();
}

class _ValidStartupNotifier extends StartupSessionNotifier {
  @override
  StartupSessionState build() {
    return StartupSessionState(
      configurationStatus: StartupConfigurationStatus.valid,
      connectivityStatus: StartupConnectivityStatus.unknown,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.light,
      deploymentProfile: sampleDeploymentProfile(),
    );
  }
}

class _ColdStartAuthRepository extends AuthRepositoryImpl {
  _ColdStartAuthRepository({required void Function() onClear})
    : _onClear = onClear,
      super(_ReloadFakeClient());

  final void Function() _onClear;

  @override
  Session? get currentSession => null;

  @override
  Future<void> clearPersistedSessionOnColdStart() async {
    _onClear();
  }

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

class _ReloadFakeClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Supabase fake whose PostgREST builders are real [Future]s so [SessionContextLoader]
/// query timeouts work in unit tests.
class _AuthSessionTableTestClient extends Fake implements SupabaseClient {
  _AuthSessionTableTestClient(this._tables);

  final Map<String, List<Map<String, dynamic>>> _tables;

  @override
  SupabaseQueryBuilder from(String table) => _AuthSessionTableQueryBuilder(_tables[table] ?? []);
}

class _AuthSessionTableQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _AuthSessionTableQueryBuilder(List<Map<String, dynamic>> rows) : _working = List<Map<String, dynamic>>.from(rows);

  final List<Map<String, dynamic>> _working;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _AuthSessionFilterBuilder(_working);
  }
}

class _AuthSessionFilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _AuthSessionFilterBuilder(List<Map<String, dynamic>> rows) : _rows = List<Map<String, dynamic>>.from(rows);

  final List<Map<String, dynamic>> _rows;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(String column, Object value) {
    _rows.retainWhere((row) => row[column] == value);
    return this;
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    return _ImmediateSingleResult(_rows.isEmpty ? null : _rows.first);
  }
}

class _ImmediateSingleResult extends Fake implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _ImmediateSingleResult(this._value);

  final Map<String, dynamic>? _value;

  @override
  Future<Map<String, dynamic>?> timeout(
    Duration timeLimit, {
    FutureOr<Map<String, dynamic>?> onTimeout()?,
  }) {
    return Future<Map<String, dynamic>?>.value(_value).timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Future<S> then<S>(
    FutureOr<S> Function(Map<String, dynamic>? value) onValue, {
    Function? onError,
  }) {
    return Future<Map<String, dynamic>?>.value(_value).then(onValue, onError: onError);
  }
}
