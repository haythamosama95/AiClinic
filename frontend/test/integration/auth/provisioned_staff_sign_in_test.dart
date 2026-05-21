import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/data/auth_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/pump_auth_app.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:ai_clinic/testing/startup_test_support.dart';

class _ProvisionedStaffSessionNotifier extends TestAuthSessionNotifier {
  @override
  Future<void> syncAfterSignIn() async {
    setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: AuthSessionContext(
          staffProfile: const StaffProfile(
            staffMemberId: '6ac96e44-a1b9-43b0-97f4-a19f275c612e',
            fullName: 'Front Desk',
            role: StaffRole.receptionist,
            isBootstrapAdmin: false,
            isActive: true,
          ),
          organizationId: 'd92b0d8a-8da6-4648-9acc-34e152e32d74',
          branchIds: const ['827c9580-e6fa-4424-9321-f3e94a5aae1e'],
          activeBranchId: '827c9580-e6fa-4424-9321-f3e94a5aae1e',
          permissions: const {'patients.read'},
          setupRequired: false,
        ),
      ),
    );
  }
}

class _ProvisionedStaffAuthRepository extends AuthRepository {
  _ProvisionedStaffAuthRepository() : super(_FakeSupabaseClient());

  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Stream<AuthState> get authStateChanges => const Stream.empty();

  @override
  Session? get currentSession => null;
}

class _FakeSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(SupabaseBootstrap.debugMarkReadyForTests);
  tearDown(SupabaseBootstrap.debugResetForTests);

  testWidgets('provisioned receptionist sign-in reaches home shell', (tester) async {
    await pumpAuthApp(
      tester,
      extraOverrides: [
        authSessionProvider.overrideWith(_ProvisionedStaffSessionNotifier.new),
        authRepositoryProvider.overrideWith((ref) => _ProvisionedStaffAuthRepository()),
      ],
    );
    await completeStartupBootstrap(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(appRouterProvider).go(AppRoutes.login);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'reception@clinic.local');
    await tester.enterText(find.byType(TextFormField).at(1), 'recept-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome, Front Desk'), findsOneWidget);
    expect(find.textContaining('Role: receptionist'), findsOneWidget);
    expect(container.read(authSessionProvider).context?.staffProfile.role, StaffRole.receptionist);
    expect(container.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path, AppRoutes.home);
    expect(find.text(kGenericSignInFailureMessage), findsNothing);
  });
}
