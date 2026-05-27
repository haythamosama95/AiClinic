import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/appointments/presentation/pages/appointment_placeholder_page.dart';
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

    testWidgets('user with create grant can open book placeholder', (tester) async {
      final auth = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(permissions: {PermissionKeys.appointmentsCreate}),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authSessionProvider.overrideWith(() => _PresetAuth(auth))],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: AppRoutes.appointmentsBook,
              routes: [
                GoRoute(
                  path: AppRoutes.appointmentsBook,
                  builder: (context, state) => const AppointmentPlaceholderPage(title: 'Book appointment'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book appointment'), findsOneWidget);
    });
  });
}

class _PresetAuth extends TestAuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
