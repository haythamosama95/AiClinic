import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('RolePermissionsPage', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      StaffRole role = StaffRole.administrator,
      SupabaseClient? tableClient,
    }) async {
      _TestAuthSessionNotifier.role = role;

      final client =
          tableClient ??
          SettingsTableTestClient({
            'roles_permissions': [
              {
                'role': 'administrator',
                'permission_key': 'settings.manage_branches',
                'is_granted': true,
                'is_deleted': false,
              },
              {
                'role': 'doctor',
                'permission_key': 'settings.manage_branches',
                'is_granted': false,
                'is_deleted': false,
              },
              {'role': 'administrator', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
              {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
            ],
          });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_TestAuthSessionNotifier.new),
            rolePermissionsRepositoryProvider.overrideWithValue(RolePermissionsRepositoryImpl(client)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: RolePermissionsPage(embedded: true)),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('administrator sees role columns and category-grouped permission rows', (tester) async {
      await pumpPage(tester);

      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Receptionist'), findsOneWidget);
      expect(find.text('Lab staff'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Manage Branches'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    });

    testWidgets('doctor sees permission denied message', (tester) async {
      await pumpPage(tester, role: StaffRole.doctor);

      expect(find.textContaining('administrators'), findsOneWidget);
      expect(find.text('Manage Branches'), findsNothing);
    });
  });
}

class _TestAuthSessionNotifier extends TestAuthSessionNotifier {
  static StaffRole role = StaffRole.administrator;

  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(role: role),
    );
  }
}
