import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_calendar_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_hub_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_queue_page.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/patient_test_support.dart';
import '../../support/appointment_rpc_test_client.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  GoRouter buildGuardedRouter(AuthSessionState auth) {
    return GoRouter(
      initialLocation: AppRoutes.home,
      redirect: (context, state) {
        return AuthRouteGuard.appointmentRouteRedirect(location: state.matchedLocation, auth: auth);
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(path: AppRoutes.appointments, builder: (context, state) => const AppointmentHubPage()),
        GoRoute(path: AppRoutes.appointmentsBook, builder: (context, state) => const AppointmentBookingPage()),
        GoRoute(path: AppRoutes.appointmentsQueue, builder: (context, state) => const AppointmentQueuePage()),
        GoRoute(path: AppRoutes.appointmentsCalendar, builder: (context, state) => const AppointmentCalendarPage()),
      ],
    );
  }

  Future<void> pumpRouter(WidgetTester tester, GoRouter router, AuthSessionState auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuth(auth)),
          appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
          patientRepositoryProvider.overrideWith((ref) => FakePatientRepository()),
          staffAdminRepositoryProvider.overrideWithValue(_GuardTestStaffRepo()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  AuthSessionState authWith(Set<String> permissions) {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        permissions: permissions,
        activeBranchId: '44444444-4444-4444-8444-444444444444',
        branchIds: const ['44444444-4444-4444-8444-444444444444'],
      ),
    );
  }

  group('Appointment route guards (AuthRouteGuard)', () {
    testWidgets('no appointment grants: hub and queue redirect to home', (tester) async {
      final auth = authWith({PermissionKeys.patientsView});
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.appointments);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const Key('appointments_hub_book')), findsNothing);

      router.go(AppRoutes.appointmentsQueue);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byKey(const Key('appointments_queue_list')), findsNothing);
    });

    testWidgets('cancel-only grant: hub and calendar allowed, book blocked', (tester) async {
      final auth = authWith({PermissionKeys.appointmentsCancel});
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.appointments);
      await tester.pumpAndSettle();
      expect(find.text('Appointments'), findsOneWidget);

      router.go(AppRoutes.appointmentsCalendar);
      await tester.pumpAndSettle();
      expect(find.text('Appointment calendar'), findsOneWidget);

      router.go(AppRoutes.appointmentsBook);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Duration (minutes)'), findsNothing);
    });

    testWidgets('create grant: booking page loads', (tester) async {
      final auth = authWith({PermissionKeys.appointmentsCreate, PermissionKeys.patientsView});
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.appointmentsBook);
      await tester.pumpAndSettle();

      expect(find.text('Duration (minutes)'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
    });

    testWidgets('in-page denial when navigating directly without router redirect', (tester) async {
      final auth = authWith({PermissionKeys.patientsView});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authSessionProvider.overrideWith(() => _PresetAuth(auth))],
          child: const MaterialApp(home: AppointmentBookingPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to book appointments.'), findsOneWidget);
    });

    testWidgets('queue in-page denial without any appointment grant', (tester) async {
      final auth = authWith({PermissionKeys.patientsView});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(() => _PresetAuth(auth)),
            appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
            appointmentQueueRealtimeClientProvider.overrideWithValue(
              _GuardFakeRealtime(AppointmentQueueRealtimeConnection.degraded),
            ),
          ],
          child: const MaterialApp(home: AppointmentQueuePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to view appointments.'), findsOneWidget);
    });
  });
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _GuardFakeRealtime implements AppointmentQueueRealtimeClient {
  _GuardFakeRealtime(this.connection);

  final AppointmentQueueRealtimeConnection connection;

  @override
  void subscribe({
    required String branchId,
    required AppointmentQueueRealtimeChangeCallback onAppointmentChange,
    required AppointmentQueueRealtimeStatusCallback onConnectionChanged,
  }) {
    onConnectionChanged(connection);
  }

  @override
  void unsubscribe() {}
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
