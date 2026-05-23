import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/patient_rpc_test_client.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  group('PatientDetailPage', () {
    testWidgets('trivial: shows profile, notes, visits placeholder, and audit', (tester) async {
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
          'created_by_display': 'Reception',
        },
      };

      await _pump(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      expect(find.byKey(const Key('patient_detail_profile')), findsOneWidget);
      expect(find.text('Ahmed Hassan'), findsWidgets);
      expect(find.text('209911112233'), findsOneWidget);
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('VIP patient'), findsOneWidget);
      expect(find.text('Reception'), findsOneWidget);
      expect(find.byKey(const Key('patient_visits_placeholder')), findsOneWidget);
      expect(find.textContaining('Visit records will appear'), findsOneWidget);
    });

    testWidgets('edge case: empty notes shows placeholder copy', (tester) async {
      final client = PatientRpcTestClient();
      client.rpcResults['get_patient'] = {
        'success': true,
        'data': {
          'id': '11111111-1111-4111-8111-111111111111',
          'full_name': 'No Notes',
          'branch_id': '44444444-4444-4444-8444-444444444444',
          'branch_name': 'Main',
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-02T00:00:00.000Z',
        },
      };

      await _pump(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      expect(find.text('No notes recorded.'), findsOneWidget);
    });

    testWidgets('permission denied without patients.view', (tester) async {
      await _pump(tester, _host(permissions: const {}, patientId: '11111111-1111-4111-8111-111111111111'));

      expect(find.byKey(const Key('patient_detail_permission_denied')), findsOneWidget);
      expect(find.byKey(const Key('patient_detail_loading')), findsNothing);
    });

    testWidgets('stupid usage: missing patient id shows validation message', (tester) async {
      await _pump(tester, _host(patientId: ''));

      expect(find.byKey(const Key('patient_detail_invalid_id')), findsOneWidget);
    });

    testWidgets('invalid state: archived patient shows unavailable message', (tester) async {
      final client = PatientRpcTestClient();
      client.rpcResults['get_patient'] = {
        'success': false,
        'error_code': 'PATIENT_ARCHIVED',
        'error_message': 'This patient is archived.',
      };

      await _pump(tester, _host(client: client, patientId: '11111111-1111-4111-8111-111111111111'));

      expect(find.byKey(const Key('patient_detail_archived')), findsOneWidget);
      expect(find.textContaining('archived'), findsWidgets);
      expect(find.byKey(const Key('patient_detail_profile')), findsNothing);
    });

    testWidgets('advanced: NOT_FOUND shows retry', (tester) async {
      final client = PatientRpcTestClient();
      client.rpcResults['get_patient'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Patient was not found.',
      };

      await _pump(tester, _host(client: client, patientId: '99999999-9999-4999-8999-999999999999'));

      expect(find.byKey(const Key('patient_detail_error')), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('back pops to previous route when pushed', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const Scaffold(body: Text('Home shell')),
          ),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
        ],
        initialLocation: AppRoutes.home,
      );

      await _pump(tester, _host(router: router, patientId: '11111111-1111-4111-8111-111111111111'));

      router.push('/patients/11111111-1111-4111-8111-111111111111');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Home shell'), findsOneWidget);
    });

    testWidgets('advanced: edit action visible with patients.edit', (tester) async {
      await _pump(
        tester,
        _host(
          client: PatientRpcTestClient(),
          patientId: '11111111-1111-4111-8111-111111111111',
          permissions: const {'patients.view', 'patients.edit'},
        ),
      );

      expect(find.byKey(const Key('patient_detail_edit')), findsOneWidget);
      expect(find.byKey(const Key('patient_detail_archive')), findsNothing);
    });

    testWidgets('advanced: archive action visible with patients.delete', (tester) async {
      await _pump(
        tester,
        _host(
          client: PatientRpcTestClient(),
          patientId: '11111111-1111-4111-8111-111111111111',
          permissions: const {'patients.view', 'patients.delete'},
        ),
      );

      expect(find.byKey(const Key('patient_detail_archive')), findsOneWidget);
      expect(find.byKey(const Key('patient_detail_edit')), findsNothing);
    });

    testWidgets('regression: back without stack falls back to patient list', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: AppRoutes.patients,
            builder: (context, state) => const Scaffold(body: Text('List')),
          ),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) => PatientDetailPage(patientId: state.pathParameters['patientId']),
          ),
        ],
        initialLocation: '/patients/11111111-1111-4111-8111-111111111111',
      );

      await _pump(tester, _host(router: router, patientId: '11111111-1111-4111-8111-111111111111'));

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('List'), findsOneWidget);
    });
  });
}

Widget _host({
  GoRouter? router,
  PatientRpcTestClient? client,
  required String patientId,
  Set<String> permissions = const {'patients.view'},
}) {
  final rpcClient = client ?? PatientRpcTestClient();
  final child = router != null
      ? MaterialApp.router(routerConfig: router)
      : MaterialApp(home: PatientDetailPage(patientId: patientId));

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
