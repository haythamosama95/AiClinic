import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_auth_app.dart';
import '../../support/settings_rpc_test_client.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import '../../helpers/auth_test_support.dart';
import '../../helpers/startup_test_support.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('admin settings router redirects', () {
    testWidgets('doctor deep-linking to branches is redirected to settings hub', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_DoctorSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _DoctorSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsBranches);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
      expect(find.text('Branches'), findsNothing);
    });

    testWidgets('owner can open organization admin route', (tester) async {
      final fetchClient = OrganizationFetchTestClient({
        'id': '00000000-0000-4000-8000-000000000020',
        'name': 'Test Clinic',
        'currency_code': 'USD',
        'timezone': 'UTC',
        'settings_json': {},
      });
      final rpc = SettingsRpcTestClient();
      await pumpAuthApp(
        tester,
        extraOverrides: [
          authSessionProvider.overrideWith(_OwnerSessionNotifier.new),
          organizationRepositoryProvider.overrideWithValue(
            _IntegrationOrganizationRepository(fetchClient: fetchClient, rpcClient: rpc),
          ),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(rpc)),
        ],
      );
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsOrganization,
      );
      expect(find.text('Organization name'), findsOneWidget);
    });

    testWidgets('setup_required user is redirected to bootstrap from staff admin route', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            setupRequired: true,
            permissions: {'settings.manage_staff', 'settings.manage_branches'},
          ),
        ),
      );
      container.read(appRouterProvider).go(AppRoutes.settingsStaff);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.bootstrap);
    });

    testWidgets('doctor deep-linking to permissions is redirected to settings hub', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_DoctorSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _DoctorSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.settingsPermissions);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.settings);
      expect(find.text('Role permissions'), findsNothing);
    });

    testWidgets('setup_complete legacy staff create redirects to settings staff form', (tester) async {
      await pumpAuthApp(tester, extraOverrides: [authSessionProvider.overrideWith(_OwnerSessionNotifier.new)]);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      (container.read(authSessionProvider.notifier) as _OwnerSessionNotifier).setAuthenticated();
      container.read(appRouterProvider).go(AppRoutes.staffCreate);
      await tester.pumpAndSettle();

      expect(
        container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path,
        AppRoutes.settingsStaffNew,
      );
    });

    testWidgets('unauthenticated user opening organization admin route goes to login', (tester) async {
      await pumpAuthApp(tester);
      await completeStartupBootstrap(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      container.read(appRouterProvider).go(AppRoutes.settingsOrganization);
      await tester.pumpAndSettle();

      expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.login);
    });
  });
}

class _DoctorSessionNotifier extends TestAuthSessionNotifier {
  @override
  void setAuthenticated({bool setupRequired = false}) {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
      ),
    );
  }
}

class _IntegrationOrganizationRepository extends OrganizationRepositoryImpl {
  _IntegrationOrganizationRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) {
    return OrganizationRepositoryImpl(_fetchClient).fetchProfile(organizationId: organizationId);
  }
}

class _OwnerSessionNotifier extends TestAuthSessionNotifier {
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
}
