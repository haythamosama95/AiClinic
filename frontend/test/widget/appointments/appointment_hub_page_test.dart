import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_booking_page.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_hub_page.dart';
import '../../support/appointment_rpc_test_client.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('AppointmentHubPage', () {
    testWidgets('shows hub actions when user has appointment access', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Appointments'), findsOneWidget);
      expect(find.byKey(const Key('appointments_hub_book')), findsOneWidget);
      expect(find.byKey(const Key('appointments_hub_queue')), findsOneWidget);
    });

    testWidgets('book navigates to booking page', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.appointments, builder: (_, _) => const AppointmentHubPage()),
          GoRoute(path: AppRoutes.appointmentsBook, builder: (_, _) => const AppointmentBookingPage()),
        ],
        initialLocation: AppRoutes.appointments,
      );

      await tester.pumpWidget(_host(router: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('appointments_hub_book')));
      await tester.pumpAndSettle();

      expect(find.text('Duration (minutes)'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
    });

    testWidgets('permission denied without appointment grants', (tester) async {
      await tester.pumpWidget(_host(permissions: {PermissionKeys.patientsView}));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to access appointments.'), findsOneWidget);
      expect(find.byKey(const Key('appointments_hub_book')), findsNothing);
    });
  });
}

Widget _host({GoRouter? router, Set<String> permissions = const {PermissionKeys.appointmentsCreate}}) {
  final branchId = '44444444-4444-4444-8444-444444444444';
  final child = router != null
      ? MaterialApp.router(routerConfig: router)
      : const MaterialApp(home: AppointmentHubPage());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: permissions,
              activeBranchId: branchId,
              branchIds: [branchId],
            ),
          ),
        ),
      ),
      appointmentRepositoryProvider.overrideWith((ref) => AppointmentRepository(AppointmentRpcTestClient())),
    ],
    child: child,
  );
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
