import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_pages.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../../support/patient_rpc_test_client.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  group('PatientListPage', () {
    testWidgets('trivial: shows scope toggle, search, and patient table', (tester) async {
      await _pump(tester, _host());

      expect(find.byKey(const Key('patient_scope_toggle')), findsOneWidget);
      expect(find.byKey(const Key('patient_search_field')), findsOneWidget);
      expect(find.byKey(const Key('patient_list_table')), findsOneWidget);
      expect(find.text('Test Patient'), findsOneWidget);
    });

    testWidgets('scope toggle switches to all branches and shows branch column', (tester) async {
      await _pump(tester, _host());

      await tester.tap(find.text('All branches'));
      await tester.pumpAndSettle();

      expect(find.text('Branch'), findsOneWidget);
    });

    testWidgets('stupid usage: short name shows validation without table data', (tester) async {
      await _pump(tester, _host());

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'ab');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.textContaining('at least 3 characters'), findsWidgets);
      expect(find.byKey(const Key('patient_list_table')), findsNothing);
    });

    testWidgets('advanced: debounced search invokes RPC', (tester) async {
      final client = PatientRpcTestClient();
      await _pump(tester, _host(client: client));

      client.lastFunction = null;
      await tester.enterText(find.byKey(const Key('patient_search_field')), 'ahmed');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(client.lastFunction, 'search_patients');
      expect(client.lastParams?['p_query'], 'ahmed');
    });

    testWidgets('empty state offers register when user can create', (tester) async {
      final client = PatientRpcTestClient();
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {'items': [], 'total_count': 0, 'limit': 25, 'offset': 0},
      };

      await _pump(tester, _host(client: client));

      expect(find.byKey(const Key('patient_list_empty_register')), findsOneWidget);
    });

    testWidgets('permission denied without patients.view', (tester) async {
      await _pump(tester, _host(permissions: const {}));

      expect(find.text('You do not have permission to view patients.'), findsOneWidget);
      expect(find.byKey(const Key('patient_search_field')), findsNothing);
    });

    testWidgets('FAB navigates to register when permitted', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientListPage()),
          GoRoute(
            path: AppRoutes.patientsNew,
            builder: (context, state) => const Scaffold(body: Text('Register page')),
          ),
        ],
        initialLocation: AppRoutes.patients,
      );

      await _pump(tester, _host(router: router, permissions: const {'patients.view', 'patients.create'}));

      await tester.tap(find.byKey(const Key('patient_list_register_fab')));
      await tester.pumpAndSettle();

      expect(find.text('Register page'), findsOneWidget);
    });

    testWidgets('tapping a row navigates to patient detail', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.patients, builder: (context, state) => const PatientListPage()),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
        ],
        initialLocation: AppRoutes.patients,
      );

      await _pump(tester, _host(router: router));

      await tester.tap(find.text('Test Patient'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_detail_profile')), findsOneWidget);
      expect(find.text('Test Patient'), findsWidgets);
    });

    testWidgets('regression: clear search resets list', (tester) async {
      final client = PatientRpcTestClient();
      await _pump(tester, _host(client: client));

      await tester.enterText(find.byKey(const Key('patient_search_field')), 'ahmed');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('patient_search_clear')));
      await tester.pumpAndSettle();

      expect(client.lastParams?.containsKey('p_query'), isFalse);
    });
  });
}

Widget _host({
  GoRouter? router,
  PatientRpcTestClient? client,
  Set<String> permissions = const {'patients.view', 'patients.create'},
}) {
  final rpcClient = client ?? PatientRpcTestClient();
  final child = router != null ? MaterialApp.router(routerConfig: router) : const MaterialApp(home: PatientListPage());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuth(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              permissions: permissions,
              activeBranchId: '44444444-4444-4444-8444-444444444444',
            ),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(rpcClient)),
      patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
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
