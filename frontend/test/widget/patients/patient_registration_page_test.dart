import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_registration_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';
import '../../support/patient_rpc_test_client.dart';

Future<void> _pumpPage(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> _tapRegister(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('patient_register_submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('PatientRegistrationPage', () {
    testWidgets('trivial: shows form fields and register button', (tester) async {
      await _pumpPage(tester, _host());

      expect(find.text('Register patient'), findsWidgets);
      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Marital status'), findsOneWidget);
    });

    testWidgets('stupid usage: empty name blocked on submit', (tester) async {
      await _pumpPage(tester, _host());

      await _tapRegister(tester);

      expect(find.text('Full name is required.'), findsOneWidget);
    });

    testWidgets('stupid usage: empty mobile blocked on submit', (tester) async {
      await _pumpPage(tester, _host());

      await tester.enterText(find.byType(TextFormField).first, 'New Patient');
      await _tapRegister(tester);

      expect(find.text('Mobile number is required.'), findsOneWidget);
    });

    testWidgets('advanced: successful register navigates to patient detail', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: AppRoutes.patientsNew, builder: (context, state) => const PatientRegistrationPage()),
          GoRoute(
            path: '${AppRoutes.patients}/:patientId',
            builder: (context, state) => Scaffold(body: Text('Detail ${state.pathParameters['patientId']}')),
          ),
        ],
        initialLocation: AppRoutes.patientsNew,
      );

      await _pumpPage(tester, _host(router: router));

      await tester.enterText(find.byType(TextFormField).at(0), 'New Patient');
      await tester.enterText(find.byType(TextFormField).at(1), '201005551234');
      await _tapRegister(tester);

      expect(find.textContaining('33333333-3333-4333-8333-333333333333'), findsOneWidget);
      expect(find.text('Patient registered successfully.'), findsOneWidget);
    });

    testWidgets('advanced: DUPLICATE_WARNING shows dialog then retries with acknowledge', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpPage(tester, _host(rpcClient: client));

      await tester.enterText(find.byType(TextFormField).at(0), 'Dup Patient');
      await tester.enterText(find.byType(TextFormField).at(1), '201000000001');
      await _tapRegister(tester);

      expect(find.text('Similar patients found'), findsOneWidget);
      expect(find.text('Existing'), findsOneWidget);

      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 2);
      expect(client.lastParams?['p_acknowledge_duplicate'], true);
    });

    testWidgets('permission denied without patients.create', (tester) async {
      await _pumpPage(tester, _host(permissions: const {'patients.view'}));

      expect(find.text('You do not have permission to register patients.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Register patient'), findsNothing);
    });

    testWidgets('edge case: duplicate dialog Go back does not call RPC again', (tester) async {
      final client = _DuplicateThenSuccessClient();

      await _pumpPage(tester, _host(rpcClient: client));

      await tester.enterText(find.byType(TextFormField).at(0), 'Dup Patient');
      await tester.enterText(find.byType(TextFormField).at(1), '201000000001');
      await _tapRegister(tester);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      expect(client.createCallCount, 1);
    });
  });
}

class _DuplicateThenSuccessClient extends PatientRpcTestClient {
  int createCallCount = 0;

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'create_patient') {
      createCallCount++;
      if (createCallCount == 1) {
        lastFunction = fn;
        lastParams = params == null ? null : Map<String, dynamic>.from(params);
        return FakePostgrestRpc({
              'success': false,
              'error_code': 'DUPLICATE_WARNING',
              'error_message': 'Similar patients found',
              'data': {
                'candidates': [
                  {'id': '22222222-2222-4222-8222-222222222222', 'full_name': 'Existing', 'branch_name': 'Main'},
                ],
              },
            })
            as PostgrestFilterBuilder<T>;
      }
    }
    return super.rpc(fn, params: params, get: get);
  }
}

Widget _host({
  GoRouter? router,
  PatientRpcTestClient? rpcClient,
  Set<String> permissions = const {'patients.view', 'patients.create'},
}) {
  final client = rpcClient ?? PatientRpcTestClient();
  final child = router != null
      ? MaterialApp.router(routerConfig: router)
      : const MaterialApp(home: PatientRegistrationPage());

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(permissions: permissions),
          ),
        ),
      ),
      patientRepositoryProvider.overrideWith((ref) => PatientRepository(client)),
    ],
    child: child,
  );
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
