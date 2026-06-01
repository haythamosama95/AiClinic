import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_visit_history_section.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

  group('PatientVisitHistorySection', () {
    testWidgets('trivial: loads and shows visit metadata rows', (tester) async {
      await _pumpSection(tester, permissions: {PermissionKeys.patientsView});

      expect(find.byKey(const Key('patient_visit_history_section')), findsOneWidget);
      expect(find.byKey(Key('patient_visit_history_row_$visitId')), findsOneWidget);
      expect(find.textContaining('Dr Test'), findsOneWidget);
      expect(find.textContaining('Main'), findsOneWidget);
    });

    testWidgets('advanced: edit button opens visit documentation when user has visits.edit_soap', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: PatientVisitHistorySection(patientId: patientId)),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (context, state) => VisitDocumentationPage(visitId: state.pathParameters['visitId']),
          ),
        ],
      );

      await _pumpSection(
        tester,
        permissions: {PermissionKeys.patientsView, PermissionKeys.visitsEditSoap},
        router: router,
      );

      await tester.tap(find.byKey(Key('patient_visit_history_edit_$visitId')));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDocumentationPage), findsOneWidget);
    });

    testWidgets('advanced: clinical user without edit_soap sees detail tap but no edit button', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: PatientVisitHistorySection(patientId: patientId)),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => Text('Detail ${state.pathParameters['visitId']}'),
          ),
        ],
      );

      await _pumpSection(
        tester,
        permissions: {PermissionKeys.patientsView, PermissionKeys.visitsCreate},
        router: router,
      );

      expect(find.byKey(Key('patient_visit_history_edit_$visitId')), findsNothing);

      await tester.tap(find.byKey(Key('patient_visit_history_row_$visitId')));
      await tester.pumpAndSettle();

      expect(find.text('Detail $visitId'), findsOneWidget);
    });

    testWidgets('advanced: clinical user can open visit detail', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: PatientVisitHistorySection(patientId: patientId)),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => Text('Detail ${state.pathParameters['visitId']}'),
          ),
        ],
      );

      await _pumpSection(
        tester,
        permissions: {PermissionKeys.patientsView, PermissionKeys.visitsEditSoap},
        router: router,
      );

      await tester.tap(find.byKey(Key('patient_visit_history_row_$visitId')));
      await tester.pumpAndSettle();

      expect(find.text('Detail $visitId'), findsOneWidget);
    });

    testWidgets('invalid state: receptionist sees metadata-only caption without chevron', (tester) async {
      await _pumpSection(tester, permissions: RolePermissionSeed.receptionist);

      expect(find.byKey(const Key('patient_visit_history_metadata_only')), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('edge case: empty history shows placeholder copy', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visits': {
            'success': true,
            'data': {'items': [], 'total_count': 0, 'limit': 50, 'offset': 0},
          },
        },
      );

      await _pumpSection(tester, client: client, permissions: {PermissionKeys.patientsView});

      expect(find.byKey(const Key('patient_visit_history_empty')), findsOneWidget);
      expect(find.textContaining('No visits recorded'), findsOneWidget);
    });

    testWidgets('stupid usage: blank patient id renders nothing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PatientVisitHistorySection(patientId: '  ')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('patient_visit_history_section')), findsNothing);
    });

    testWidgets('regression: load more requests next page', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'list_patient_visits': {
            'success': true,
            'data': {
              'items': [
                {
                  'id': visitId,
                  'visit_date': '2026-05-31',
                  'doctor_name': 'Dr Test',
                  'status': 'completed',
                  'branch_name': 'Main',
                },
              ],
              'total_count': 3,
              'limit': 20,
              'offset': 0,
            },
          },
        },
      );

      await _pumpSection(tester, client: client, permissions: {PermissionKeys.patientsView});

      expect(find.byKey(const Key('patient_visit_history_load_more')), findsOneWidget);
      await tester.tap(find.byKey(const Key('patient_visit_history_load_more')));
      await tester.pumpAndSettle();

      expect(client.rpcLog.where((fn) => fn == 'list_patient_visits').length, greaterThanOrEqualTo(2));
    });
  });
}

Future<void> _pumpSection(
  WidgetTester tester, {
  Set<String> permissions = const {PermissionKeys.patientsView},
  VisitRpcTestClient? client,
  GoRouter? router,
}) async {
  const patientId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const branchId = '44444444-4444-4444-8444-444444444444';

  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: branchId, branchIds: [branchId]),
  );

  final child = ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(client ?? VisitRpcTestClient())),
    ],
    child: MaterialApp.router(
      routerConfig:
          router ??
          GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Scaffold(body: PatientVisitHistorySection(patientId: patientId)),
              ),
            ],
          ),
    ),
  );

  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
