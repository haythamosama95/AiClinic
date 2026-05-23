import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

void main() {
  group('role permissions session refresh', () {
    testWidgets('owner stays on permissions route when context reloads without loading state', (tester) async {
      final matrixClient = SettingsTableTestClient({
        'roles_permissions': [
          {'role': 'owner', 'permission_key': 'settings.manage_branches', 'is_granted': true, 'is_deleted': false},
          {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
        ],
      });
      final repo = _IntegrationRolePermissionsRepository(fetchClient: matrixClient, rpcClient: SettingsRpcTestClient());

      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_OwnerReloadSessionNotifier.new),
          rolePermissionsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final notifier = container.read(authSessionProvider.notifier) as _OwnerReloadSessionNotifier;
      notifier.setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsPermissions);
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsPermissions,
      );
      expect(find.text('Role permissions'), findsOneWidget);

      await notifier.reloadContext();
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsPermissions,
      );
      expect(find.text('Role permissions'), findsOneWidget);
      expect(container.read(authSessionProvider).status, AuthSessionStatus.authenticated);
    });
  });
}

/// Simulates a silent session refresh (no [AuthSessionStatus.loading]).
class _OwnerReloadSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.owner,
          permissions: {'settings.manage_branches', 'settings.manage_staff'},
        ),
      ),
    );
  }

  @override
  Future<void> reloadContext() async {
    final context = state.context;
    if (context == null) {
      return;
    }

    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: context.copyWith(permissions: {...context.permissions, 'analytics.view'}),
      ),
    );
  }
}

class _IntegrationRolePermissionsRepository extends RolePermissionsRepository {
  _IntegrationRolePermissionsRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<List<PermissionMatrixRow>> fetchMatrix() {
    return RolePermissionsRepository(_fetchClient).fetchMatrix();
  }
}
