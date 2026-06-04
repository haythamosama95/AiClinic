import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/soap_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

void main() {
  const visitId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  const branchId = '44444444-4444-4444-8444-444444444444';

  group('Visit documentation treatment + SOAP', () {
    testWidgets('new treatment appears in panel after add (API-shaped plan rows)', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpVisitDocSection(tester, client: client);

      await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('treatment_plan_medication_field')), 'Aspirin');
      await tester.enterText(find.byKey(const Key('treatment_plan_duration_field')), '10 days');
      client.rpcResults['get_visit'] = _visitWithPlans(
        visitId: visitId,
        branchId: branchId,
        plans: const [
          {'id': 'tttttttt-tttt-4ttt-8ttt-tttttttttttt', 'medication_name': 'Aspirin', 'duration': '10 days'},
        ],
      );
      await _tapTreatmentPlanSave(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('treatment_plan_card_tttttttt-tttt-4ttt-8ttt-tttttttttttt')), findsOneWidget);
      expect(find.text('Aspirin'), findsOneWidget);
      expect(find.textContaining('10 days'), findsOneWidget);
      expect(find.byKey(const Key('treatment_plan_empty')), findsNothing);
    });

    testWidgets('adding treatment does not clear unsaved SOAP text', (tester) async {
      final client = VisitRpcTestClient();

      await _pumpVisitDocSection(tester, client: client);

      await tester.enterText(find.byKey(const Key('soap_subjective')), 'Patient reports headache.');
      await tester.enterText(find.byKey(const Key('soap_assessment')), 'Likely tension headache.');

      await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('treatment_plan_medication_field')), 'Ibuprofen');
      client.rpcResults['get_visit'] = _visitWithPlans(
        visitId: visitId,
        branchId: branchId,
        plans: const [
          {'id': 'tttttttt-tttt-4ttt-8ttt-tttttttttttt', 'medication_name': 'Ibuprofen'},
        ],
      );
      await _tapTreatmentPlanSave(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Patient reports headache.'), findsOneWidget);
      expect(find.textContaining('Likely tension headache.'), findsOneWidget);
      expect(find.text('Ibuprofen'), findsOneWidget);
    });

    testWidgets('duration field replaces start and end date pickers', (tester) async {
      await _pumpVisitDocSection(tester);

      await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('treatment_plan_duration_field')), findsOneWidget);
      expect(find.byKey(const Key('treatment_plan_start_date')), findsNothing);
      expect(find.byKey(const Key('treatment_plan_end_date')), findsNothing);
    });

    testWidgets('completed visit allows adding treatment plans', (tester) async {
      final client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': _visitWithPlans(visitId: visitId, branchId: branchId, plans: const [], status: 'completed'),
        },
      );

      await _pumpVisitDocSection(tester, client: client);

      expect(find.byKey(const Key('treatment_plan_add_button')), findsOneWidget);
    });
  });
}

Map<String, dynamic> _visitWithPlans({
  required String visitId,
  required String branchId,
  required List<Map<String, String>> plans,
  String status = 'in_progress',
}) {
  return {
    'success': true,
    'data': {
      'id': visitId,
      'branch_id': branchId,
      'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Test',
      'visit_date': '2026-05-31',
      'status': status,
      'soap': {
        'subjective': null,
        'objective': null,
        'assessment': null,
        'plan': null,
        'specialty_form_json': {},
        'updated_at': '2026-05-31T10:00:00.000Z',
      },
      'treatment_plans': plans,
    },
  };
}

Future<void> _tapTreatmentPlanSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('treatment_plan_save_button')),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
}

Future<void> _pumpVisitDocSection(WidgetTester tester, {VisitRpcTestClient? client}) async {
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _PresetAuth(authState)),
        visitRepositoryProvider.overrideWith((ref) {
          final effective = client ?? VisitRpcTestClient();
          effective.rpcResults.putIfAbsent(
            'get_specialty_form_schema',
            () => {
              'success': true,
              'data': {
                'schema_json': {'type': 'object', 'properties': {}},
              },
            },
          );
          return VisitRepository(effective);
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(visitDocumentationProvider(visitId));
              return async.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (state) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SoapEditor(visitId: visitId, state: state),
                      const SizedBox(height: 24),
                      TreatmentPlanList(
                        visitId: visitId,
                        treatmentPlans: state.visit.treatmentPlans,
                        canEdit: state.isEditable,
                        onChanged: () => ref
                            .read(visitDocumentationProvider(visitId).notifier)
                            .refreshTreatmentPlansPreservingDraft(),
                      ),
                    ],
                  ),
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

class _PresetAuth extends AuthSessionNotifier {
  _PresetAuth(this._state);
  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
