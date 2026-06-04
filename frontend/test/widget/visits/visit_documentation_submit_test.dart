import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  testWidgets('submit visit saves unsaved SOAP before complete_visit', (tester) async {
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
            'status': 'in_progress',
            'soap': {
              'subjective': null,
              'objective': null,
              'assessment': null,
              'plan': null,
              'specialty_form_json': {},
              'updated_at': '2026-05-31T10:00:00.000Z',
            },
            'treatment_plans': [],
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

    await tester.enterText(find.byKey(const Key('soap_subjective')), 'Chief complaint documented.');
    await tester.tap(find.byKey(const Key('visit_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('visit_submit_dialog')), findsOneWidget);

    final saveIndex = client.rpcLog.indexOf('save_soap_note');
    final completeIndex = client.rpcLog.indexOf('complete_visit');
    expect(saveIndex, greaterThanOrEqualTo(0));
    expect(completeIndex, lessThan(0));

    await tester.tap(find.byKey(const Key('visit_submit_confirm_button')));
    await tester.pumpAndSettle();

    expect(client.rpcLog.indexOf('save_soap_note'), lessThan(client.rpcLog.indexOf('complete_visit')));
    final saveParams = client.paramsForFunction('save_soap_note')!;
    expect(saveParams['p_subjective'], 'Chief complaint documented.');
    expect(find.text('Visit submitted. The linked appointment is now completed.'), findsOneWidget);
  });
}

Widget _host({required VisitRpcTestClient client}) {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      permissions: {PermissionKeys.visitsEditSoap},
      activeBranchId: branchId,
      branchIds: [branchId],
    ),
  );

  return ProviderScope(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuth(authState)),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: AppRoutes.visitDocument(visitId),
        routes: [
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
