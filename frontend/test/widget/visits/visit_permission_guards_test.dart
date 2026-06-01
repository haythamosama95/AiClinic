import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  setUp(() {
    SupabaseBootstrap.debugMarkReadyForTests();
  });

  tearDown(() {
    SupabaseBootstrap.debugResetForTests();
  });

  AuthSessionState authWith(Set<String> permissions) {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        permissions: permissions,
        activeBranchId: branchId,
        branchIds: const [branchId],
      ),
    );
  }

  GoRouter buildGuardedRouter(AuthSessionState auth) {
    return GoRouter(
      initialLocation: AppRoutes.home,
      redirect: (context, state) {
        return AuthRouteGuard.visitRouteRedirect(location: state.matchedLocation, auth: auth);
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
          builder: (context, state) => VisitDocumentationPage(visitId: state.pathParameters['visitId']),
        ),
        GoRoute(
          path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
          builder: (context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']),
        ),
      ],
    );
  }

  Future<void> pumpRouter(WidgetTester tester, GoRouter router, AuthSessionState auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuth(auth)),
          visitRepositoryProvider.overrideWith((ref) => VisitRepository(VisitRpcTestClient())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Visit route guards (AuthRouteGuard)', () {
    test('receptionist without visit keys: documentation and detail redirect to home', () {
      final auth = authWith(RolePermissionSeed.receptionist);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDocument(visitId), auth: auth), AppRoutes.home);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDetail(visitId), auth: auth), AppRoutes.home);
    });

    test('doctor with visits.edit_soap: documentation allowed, detail allowed', () {
      final auth = authWith(RolePermissionSeed.doctor);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDocument(visitId), auth: auth), isNull);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDetail(visitId), auth: auth), isNull);
    });

    test('lab staff: detail allowed via upload grant, documentation blocked', () {
      final auth = authWith(RolePermissionSeed.labStaff);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDocument(visitId), auth: auth), AppRoutes.home);
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDetail(visitId), auth: auth), isNull);
    });

    test('visits.create without edit_soap: documentation allowed', () {
      final auth = authWith({PermissionKeys.visitsCreate});
      expect(AuthRouteGuard.visitRouteRedirect(location: AppRoutes.visitDocument(visitId), auth: auth), isNull);
    });

    testWidgets('no visit grants: navigating to documentation shows home', (tester) async {
      final auth = authWith({PermissionKeys.patientsView});
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.visitDocument(visitId));
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(VisitDocumentationPage), findsNothing);
    });

    testWidgets('doctor: documentation route renders page', (tester) async {
      final auth = authWith(RolePermissionSeed.doctor);
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.visitDocument(visitId));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDocumentationPage), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('lab staff: detail route renders, SOAP editor absent on documentation redirect', (tester) async {
      final auth = authWith(RolePermissionSeed.labStaff);
      final router = buildGuardedRouter(auth);
      await pumpRouter(tester, router, auth);

      router.go(AppRoutes.visitDetail(visitId));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDetailPage), findsOneWidget);

      router.go(AppRoutes.visitDocument(visitId));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });
  });
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
