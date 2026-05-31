import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/soap_editor.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  group('SoapEditor', () {
    testWidgets('trivial: renders four SOAP fields when user can edit', (tester) async {
      await _pumpEditor(tester, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byKey(const Key('soap_subjective')), findsOneWidget);
      expect(find.byKey(const Key('soap_objective')), findsOneWidget);
      expect(find.byKey(const Key('soap_assessment')), findsOneWidget);
      expect(find.byKey(const Key('soap_plan')), findsOneWidget);
      expect(find.byKey(const Key('soap_save_button')), findsOneWidget);
    });

    testWidgets('trivial: read-only when user lacks visits.edit_soap', (tester) async {
      await _pumpEditor(tester, permissions: {PermissionKeys.visitsCreate});

      expect(find.byKey(const Key('soap_save_button')), findsNothing);
      expect(find.text('Subjective'), findsOneWidget);
    });

    testWidgets('advanced: successful save shows saved label', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpEditor(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('soap_subjective')), 'Patient reports pain.');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('save_soap_note'));
      expect(find.byKey(const Key('soap_saved_label')), findsOneWidget);
    });

    testWidgets('invalid state: STALE_SOAP shows reload banner', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'save_soap_note': {'success': false, 'error_code': 'STALE_SOAP', 'error_message': 'Stale'},
        },
      );

      await _pumpEditor(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('soap_subjective')), 'Updated elsewhere.');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('soap_stale_banner')), findsOneWidget);
      expect(find.textContaining('updated elsewhere'), findsOneWidget);
      expect(find.byKey(const Key('soap_reload_button')), findsOneWidget);
    });

    testWidgets('edge case: completed visit shows read-only caption', (tester) async {
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
        },
      );

      await _pumpEditor(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byKey(const Key('soap_save_button')), findsNothing);
      expect(find.textContaining('cannot be edited'), findsOneWidget);
    });

    testWidgets('stupid usage: save with empty sections still calls RPC', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpEditor(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('save_soap_note'));
    });

    testWidgets('regression: reload after stale refetches visit', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'save_soap_note': {
            'success': false,
            'error_code': 'STALE_SOAP',
            'error_message': 'Stale',
          },
        },
      );

      await _pumpEditor(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      client.rpcResults['save_soap_note'] = {
        'success': false,
        'error_code': 'STALE_SOAP',
        'error_message': 'Stale',
      };

      await tester.enterText(find.byKey(const Key('soap_subjective')), 'Draft');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      client.rpcResults.remove('save_soap_note');
      client.rpcResults['get_visit'] = {
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
            'subjective': 'Server copy',
            'objective': null,
            'assessment': null,
            'plan': null,
            'specialty_form_json': {},
            'updated_at': '2026-05-31T11:00:00.000Z',
          },
        },
      };

      await tester.tap(find.byKey(const Key('soap_reload_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('soap_stale_banner')), findsNothing);
      expect(find.textContaining('Server copy'), findsOneWidget);
    });
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  Set<String> permissions = const {PermissionKeys.visitsEditSoap},
  VisitRpcTestClient? client,
}) async {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  final authState = AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: branchId, branchIds: [branchId]),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(authState)),
        visitRepositoryProvider.overrideWith((ref) => VisitRepository(client ?? VisitRpcTestClient())),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(visitDocumentationProvider(visitId));
              return async.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (state) => SoapEditor(visitId: visitId, state: state),
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
