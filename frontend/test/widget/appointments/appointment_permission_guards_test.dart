import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_placeholder_page.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  GoRouter buildRouter(AuthSessionState auth) {
    return GoRouter(
      initialLocation: AppRoutes.home,
      redirect: (context, state) {
        final location = state.matchedLocation;
        if (location == AppRoutes.appointmentsBook) {
          final allowed = auth.context?.permissions.contains(PermissionKeys.appointmentsCreate) ?? false;
          return allowed ? null : AppRoutes.home;
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: AppRoutes.appointmentsBook,
          builder: (context, state) => const AppointmentPlaceholderPage(title: 'Book appointment'),
        ),
      ],
    );
  }

  group('Appointment route guards', () {
    testWidgets('user without create grant redirected from book route', (tester) async {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.patientsView}),
      );
      final router = buildRouter(auth);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authSessionProvider.overrideWith(() => _PresetAuth(auth))],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      router.go(AppRoutes.appointmentsBook);
      await tester.pumpAndSettle();

      expect(find.text('Book appointment'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('user with create grant can open booking page', (tester) async {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          permissions: {PermissionKeys.appointmentsCreate},
          activeBranchId: '44444444-4444-4444-8444-444444444444',
          branchIds: const ['44444444-4444-4444-8444-444444444444'],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(() => _PresetAuth(auth)),
            appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
            patientRepositoryProvider.overrideWith((ref) => FakePatientRepository()),
            staffAdminRepositoryProvider.overrideWithValue(_GuardTestStaffRepo()),
          ],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: AppRoutes.appointmentsBook,
              routes: [
                GoRoute(path: AppRoutes.appointmentsBook, builder: (context, state) => const AppointmentBookingPage()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book appointment'), findsWidgets);
      expect(find.text('Duration (minutes)'), findsOneWidget);
    });
  });
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _GuardTestStaffRepo implements StaffAdminRepository {
  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async => const [];

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<bool> organizationHasOwner() => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();
}
