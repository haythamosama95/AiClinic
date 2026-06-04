import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_detail_page.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  group('VisitDetailPage', () {
    testWidgets('loads visit from backend and shows treatment plans', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': visitId,
              'branch_id': branchId,
              'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'completed',
              'soap': {
                'subjective': 'Headache',
                'objective': null,
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
              'treatment_plans': [
                {'id': 'tttttttt-tttt-4ttt-8ttt-tttttttttttt', 'medication_name': 'Ibuprofen', 'duration': '7 days'},
              ],
            },
          },
          'get_specialty_form_schema': {
            'success': true,
            'data': {
              'schema_json': {'type': 'object', 'properties': {}},
            },
          },
        },
      );

      await tester.pumpWidget(_host(client: client));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('get_visit'));
      expect(find.byKey(const Key('visit_detail_body')), findsOneWidget);
      expect(find.text('Treatment plans'), findsOneWidget);
      expect(find.text('Ibuprofen'), findsOneWidget);
      expect(find.textContaining('7 days'), findsOneWidget);
    });

    testWidgets('completed visit with edit permission shows Edit visit action', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': visitId,
              'branch_id': branchId,
              'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'completed',
              'soap': {
                'subjective': 'Done',
                'objective': null,
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
          'get_specialty_form_schema': {
            'success': true,
            'data': {
              'schema_json': {'type': 'object', 'properties': {}},
            },
          },
        },
      );

      await tester.pumpWidget(_host(client: client, permissions: {PermissionKeys.visitsEditSoap}));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_detail_edit_documentation')), findsOneWidget);
      expect(find.text('Edit visit'), findsOneWidget);

      await tester.tap(find.byKey(const Key('visit_detail_edit_documentation')));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDocumentationPage), findsOneWidget);
    });

    testWidgets('completed visit shows attachment download without upload or edit', (tester) async {
      const attachmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': visitId,
              'branch_id': branchId,
              'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'completed',
              'soap': {
                'subjective': 'Done',
                'objective': null,
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
              'attachments': [
                {
                  'id': attachmentId,
                  'file_type': 'pdf',
                  'label': 'Lab result',
                  'uploaded_by': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                  'uploaded_by_name': 'Dr Test',
                  'size_bytes': 2048,
                  'created_at': '2026-05-31T10:00:00.000Z',
                  'can_download': true,
                },
              ],
            },
          },
          'get_specialty_form_schema': {
            'success': true,
            'data': {
              'schema_json': {'type': 'object', 'properties': {}},
            },
          },
        },
      );

      await tester.pumpWidget(_host(client: client, permissions: {PermissionKeys.patientsView}));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_detail_edit_documentation')), findsNothing);
      expect(find.byKey(const Key('visit_attachment_upload_button')), findsNothing);
      expect(find.byKey(Key('visit_attachment_download_$attachmentId')), findsOneWidget);
      expect(find.text('Lab result'), findsOneWidget);
    });

    testWidgets('hides edit action without visits.edit_soap', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': {
            'success': true,
            'data': {
              'id': visitId,
              'branch_id': branchId,
              'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'doctor_name': 'Dr Test',
              'visit_date': '2026-05-31',
              'status': 'completed',
              'soap': {
                'subjective': 'Done',
                'objective': null,
                'assessment': null,
                'plan': null,
                'specialty_form_json': {},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
          'get_specialty_form_schema': {
            'success': true,
            'data': {
              'schema_json': {'type': 'object', 'properties': {}},
            },
          },
        },
      );

      await tester.pumpWidget(_host(client: client, permissions: {PermissionKeys.visitsCreate}));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit_detail_edit_documentation')), findsNothing);
    });
  });
}

Widget _host({required VisitRpcTestClient client, Set<String> permissions = const {PermissionKeys.visitsCreate}}) {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: branchId, branchIds: [branchId]),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.visitDetail(visitId),
        routes: [
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDetailSegment}',
            builder: (context, state) => VisitDetailPage(visitId: state.pathParameters['visitId']),
          ),
          GoRoute(
            path: '${AppRoutes.visits}/:visitId/${AppRoutes.visitDocumentSegment}',
            builder: (context, state) => VisitDocumentationPage(visitId: state.pathParameters['visitId']),
          ),
        ],
      ),
    ),
  );
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
