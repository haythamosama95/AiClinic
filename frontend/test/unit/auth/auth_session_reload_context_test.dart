import 'dart:convert';

import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/data/permission_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/settings_table_test_client.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
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
    final supabaseClient = SettingsTableTestClient({
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
    container.dispose();
  });

  test('reloadContext refreshes session and reloads permission grants', () async {
    var permissionLoads = 0;
    var refreshCalls = 0;
    final session = _fakeSession();
    final supabaseClient = SettingsTableTestClient({
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
}

class _ReloadHarnessNotifier extends AuthSessionNotifier {
  @override
  AuthSessionState build() => const AuthSessionState(status: AuthSessionStatus.unauthenticated);
}

class _ReloadAuthRepository extends AuthRepository {
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
  Stream<AuthState> get authStateChanges => const Stream.empty();
}

class _ReloadPermissionRepository extends PermissionRepository {
  _ReloadPermissionRepository({required Future<Set<String>> Function() onLoad})
    : _onLoad = onLoad,
      super(_ReloadFakeClient());

  final Future<Set<String>> Function() _onLoad;

  @override
  Future<Set<String>> loadGrantedPermissions(StaffRole role) => _onLoad();
}

class _ReloadFakeClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
