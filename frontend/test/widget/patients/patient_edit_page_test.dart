import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_edit_page.dart';
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

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('patient_edit_submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('PatientEditPage', () {
    testWidgets('trivial: loads patient into form fields', (tester) async {
      final client = _detailClient();

      await _pumpPage(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      expect(find.byKey(const Key('patient_edit_body')), findsOneWidget);
      expect(find.text('Main'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Ahmed Hassan'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '209911112233'), findsOneWidget);
      expect(find.text('VIP patient'), findsOneWidget);
    });

    testWidgets('advanced: successful save navigates to detail', (tester) async {
      final client = _TrackingUpdateClient();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/patients/:patientId/edit',
            builder: (context, state) => PatientEditPage(patientId: state.pathParameters['patientId']),
          ),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => Scaffold(body: Text('Detail ${state.pathParameters['patientId']}')),
          ),
        ],
        initialLocation: '/patients/11111111-1111-4111-8111-111111111111/edit',
      );

      await _pumpPage(tester, _host(router: router, client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      await tester.enterText(find.byType(TextFormField).at(0), 'Ahmed Updated');
      await _tapSave(tester);

      expect(find.textContaining('11111111-1111-4111-8111-111111111111'), findsOneWidget);
      expect(find.text('Patient updated successfully.'), findsOneWidget);
      expect(client.updateCallCount, 1);
    });

    testWidgets('advanced: STALE_PATIENT shows reload banner', (tester) async {
      final client = _StaleUpdateClient();

      await _pumpPage(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      await tester.enterText(find.byType(TextFormField).at(0), 'Stale edit');
      await _tapSave(tester);

      expect(find.byKey(const Key('patient_edit_stale_banner')), findsOneWidget);
      expect(find.textContaining('updated elsewhere'), findsOneWidget);
    });

    testWidgets('advanced: DUPLICATE_WARNING shows dialog then retries', (tester) async {
      final client = _DuplicateThenSuccessUpdateClient();

      await _pumpPage(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      await tester.enterText(find.byType(TextFormField).at(1), '209900000099');
      await _tapSave(tester);

      expect(find.text('Similar patients found'), findsOneWidget);
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();

      expect(client.updateCallCount, 2);
      expect(client.lastUpdateParams?['p_acknowledge_duplicate'], true);
    });

    testWidgets('permission denied without patients.edit', (tester) async {
      await _pumpPage(
        tester,
        _host(patientId: '11111111-1111-4111-8111-111111111111', permissions: const {'patients.view'}),
      );

      expect(find.byKey(const Key('patient_edit_permission_denied')), findsOneWidget);
      expect(find.byKey(const Key('patient_edit_submit')), findsNothing);
    });

    testWidgets('stupid usage: missing patient id shows validation message', (tester) async {
      await _pumpPage(tester, _host(patientId: ''));

      expect(find.byKey(const Key('patient_edit_invalid_id')), findsOneWidget);
    });

    testWidgets('stupid usage: empty name blocked on submit', (tester) async {
      await _pumpPage(tester, _host(client: _detailClient(), patientId: '11111111-1111-4111-8111-111111111111'));

      await tester.enterText(find.byType(TextFormField).at(0), '   ');
      await _tapSave(tester);

      expect(find.text('Full name is required.'), findsOneWidget);
      expect(find.text('Patient updated successfully.'), findsNothing);
    });

    testWidgets('regression: stale reload refetches patient', (tester) async {
      final client = _StaleUpdateClient();

      await _pumpPage(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      await _tapSave(tester);
      expect(find.byKey(const Key('patient_edit_stale_banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('patient_edit_stale_reload')));
      await tester.pumpAndSettle();

      expect(client.getCallCount, greaterThanOrEqualTo(2));
      expect(find.byKey(const Key('patient_edit_stale_banner')), findsNothing);
    });
  });
}

class _TrackingUpdateClient extends PatientRpcTestClient {
  int updateCallCount = 0;

  _TrackingUpdateClient() {
    rpcResults['get_patient'] = {
      'success': true,
      'data': {
        'id': '11111111-1111-4111-8111-111111111111',
        'full_name': 'Ahmed Hassan',
        'phone': '209911112233',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'branch_name': 'Main',
        'created_at': '2026-01-01T08:00:00.000Z',
        'updated_at': '2026-01-02T09:30:00.000Z',
      },
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_patient') {
      updateCallCount++;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

PatientRpcTestClient _detailClient() {
  final client = PatientRpcTestClient();
  client.rpcResults['get_patient'] = {
    'success': true,
    'data': {
      'id': '11111111-1111-4111-8111-111111111111',
      'full_name': 'Ahmed Hassan',
      'phone': '209911112233',
      'date_of_birth': '1990-05-15',
      'gender': 'male',
      'marital_status': 'married',
      'notes': 'VIP patient',
      'branch_id': '44444444-4444-4444-8444-444444444444',
      'branch_name': 'Main',
      'created_at': '2026-01-01T08:00:00.000Z',
      'updated_at': '2026-01-02T09:30:00.000Z',
    },
  };
  return client;
}

class _StaleUpdateClient extends PatientRpcTestClient {
  int getCallCount = 0;

  _StaleUpdateClient() {
    rpcResults['get_patient'] = {
      'success': true,
      'data': {
        'id': '11111111-1111-4111-8111-111111111111',
        'full_name': 'Ahmed Hassan',
        'phone': '209911112233',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'branch_name': 'Main',
        'created_at': '2026-01-01T08:00:00.000Z',
        'updated_at': '2026-01-02T09:30:00.000Z',
      },
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'get_patient') {
      getCallCount++;
    }
    if (fn == 'update_patient') {
      return FakePostgrestRpc({'success': false, 'error_code': 'STALE_PATIENT', 'error_message': 'Stale'})
          as PostgrestFilterBuilder<T>;
    }
    return super.rpc(fn, params: params, get: get);
  }
}

class _DuplicateThenSuccessUpdateClient extends PatientRpcTestClient {
  int updateCallCount = 0;
  Map<String, dynamic>? lastUpdateParams;

  _DuplicateThenSuccessUpdateClient() {
    rpcResults['get_patient'] = {
      'success': true,
      'data': {
        'id': '11111111-1111-4111-8111-111111111111',
        'full_name': 'Ahmed Hassan',
        'phone': '209911112233',
        'branch_id': '44444444-4444-4444-8444-444444444444',
        'branch_name': 'Main',
        'created_at': '2026-01-01T08:00:00.000Z',
        'updated_at': '2026-01-02T09:30:00.000Z',
      },
    };
  }

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    if (fn == 'update_patient') {
      updateCallCount++;
      lastUpdateParams = params == null ? null : Map<String, dynamic>.from(params);
      if (updateCallCount == 1) {
        lastFunction = fn;
        lastParams = lastUpdateParams;
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
  PatientRpcTestClient? client,
  required String patientId,
  Set<String> permissions = const {'patients.view', 'patients.edit'},
}) {
  final rpcClient = client ?? _detailClient();
  final child = router != null
      ? MaterialApp.router(routerConfig: router)
      : MaterialApp(home: PatientEditPage(patientId: patientId));

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
      patientRepositoryProvider.overrideWith((ref) => PatientRepository(rpcClient)),
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
