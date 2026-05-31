import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_documentation_page.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/specialty_form_fields.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  group('SpecialtyFormFields', () {
    testWidgets('trivial: renders number, checkbox, and select when schema has fields', (tester) async {
      await _pumpFields(tester, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byKey(const Key('specialty_field_pain_score')), findsOneWidget);
      expect(find.byKey(const Key('specialty_field_follow_up')), findsOneWidget);
      expect(find.byKey(const Key('specialty_field_site')), findsOneWidget);
      expect(find.text('Pain score'), findsWidgets);
    });

    testWidgets('trivial: hidden when schema has no properties', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_specialty_form_schema': {
            'success': true,
            'data': {'schema_json': {}},
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byKey(const Key('specialty_field_pain_score')), findsNothing);
    });

    testWidgets('shows info banner when schema empty and user can edit SOAP', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_specialty_form_schema': {
            'success': true,
            'data': {'schema_json': {}},
          },
        },
      );

      await _pumpDocumentation(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byKey(const Key('specialty_schema_empty_banner')), findsOneWidget);
      expect(find.textContaining('No specialty form configured'), findsOneWidget);
      expect(find.byKey(const Key('specialty_schema_settings_link')), findsOneWidget);
    });

    testWidgets('advanced: client validation shows required error before RPC', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.tap(find.byKey(const Key('specialty_field_follow_up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('specialty_error_pain_score')), findsOneWidget);
      expect(client.rpcLog, isNot(contains('save_soap_note')));
    });

    testWidgets('advanced: successful save sends specialty JSON to RPC', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('specialty_field_pain_score')), '6');
      await tester.tap(find.byKey(const Key('specialty_field_follow_up')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('save_soap_note'));
      final saveParams = client.paramsForFunction('save_soap_note');
      expect(saveParams?['p_specialty_form_json'], isA<Map>());
      final specialty = saveParams!['p_specialty_form_json'] as Map;
      expect(specialty['pain_score'], 6);
      expect(specialty['follow_up'], isTrue);
    });

    testWidgets('invalid state: backend INVALID_INPUT surfaces on save', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'save_soap_note': {
            'success': false,
            'error_code': 'INVALID_INPUT',
            'error_message': 'Specialty form data is not valid.',
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('specialty_field_pain_score')), '2');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('soap_error_label')), findsOneWidget);
    });

    testWidgets('advanced: select field value is included in save payload', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('specialty_field_pain_score')), '3');
      await tester.tap(find.byKey(const Key('specialty_field_site')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('leg').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      final specialty = client.paramsForFunction('save_soap_note')!['p_specialty_form_json'] as Map;
      expect(specialty['site'], 'leg');
    });

    testWidgets('invalid state: non-numeric pain score blocks save with field error', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.enterText(find.byKey(const Key('specialty_field_pain_score')), 'abc');
      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('specialty_error_pain_score')), findsOneWidget);
      expect(client.rpcLog, isNot(contains('save_soap_note')));
    });

    testWidgets('trivial: read-only when user lacks visits.edit_soap', (tester) async {
      await _pumpFields(tester, permissions: {PermissionKeys.visitsCreate});

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('advanced: restores saved specialty values from visit SOAP', (tester) async {
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
                'subjective': 'Note',
                'specialty_form_json': {'pain_score': 8, 'follow_up': true, 'site': 'arm'},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.widgetWithText(TextField, '8'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('specialty_field_follow_up'))).value, isTrue);
    });

    testWidgets('edge case: empty schema allows save without specialty payload', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_specialty_form_schema': {
            'success': true,
            'data': {'schema_json': {}},
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      await tester.tap(find.byKey(const Key('soap_save_button')));
      await tester.pumpAndSettle();

      expect(client.rpcLog, contains('save_soap_note'));
      expect(client.paramsForFunction('save_soap_note')?['p_specialty_form_json'], isNull);
    });

    testWidgets('edge case: read-only when visit completed', (tester) async {
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
                'specialty_form_json': {'pain_score': 2},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.byType(TextField), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Yes'), findsNothing);
    });

    testWidgets('edge case: completed visit shows boolean as Yes/No', (tester) async {
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
                'specialty_form_json': {'pain_score': 2, 'follow_up': true},
                'updated_at': '2026-05-31T10:00:00.000Z',
              },
            },
          },
        },
      );

      await _pumpFields(tester, client: client, permissions: {PermissionKeys.visitsEditSoap});

      expect(find.text('Yes'), findsOneWidget);
    });
  });
}

Future<void> _pumpFields(
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
                data: (state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SpecialtyFormFields(visitId: visitId, state: state),
                    const SizedBox(height: 16),
                    // Reuse SOAP save button from SoapEditor pattern for integration in tests.
                    if (state.canEdit && state.isEditable)
                      FilledButton(
                        key: const Key('soap_save_button'),
                        onPressed: () => ref.read(visitDocumentationProvider(visitId).notifier).save(),
                        child: const Text('Save SOAP'),
                      ),
                    if (state.saveStatus == SoapSaveStatus.error && state.errorMessage != null)
                      Text(state.errorMessage!, key: const Key('soap_error_label')),
                    for (final entry in state.specialtyFieldErrors.entries)
                      Text(entry.value, key: Key('specialty_error_${entry.key}')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

Future<void> _pumpDocumentation(
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
      child: MaterialApp(home: VisitDocumentationPage(visitId: visitId)),
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
