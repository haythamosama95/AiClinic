import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';

import '../../support/visit_rpc_test_client.dart';

void main() {
  late VisitRpcTestClient testClient;

  setUp(() {
    testClient = VisitRpcTestClient();
  });

  Widget buildWidget({List<TreatmentPlanItem> plans = const [], bool canEdit = true, VoidCallback? onChanged}) {
    return ProviderScope(
      overrides: [visitRepositoryProvider.overrideWithValue(VisitRepository(testClient))],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TreatmentPlanList(
              visitId: 'visit-1',
              treatmentPlans: plans,
              canEdit: canEdit,
              onChanged: onChanged ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows empty state when no plans', (tester) async {
    await tester.pumpWidget(buildWidget());
    expect(find.byKey(const Key('treatment_plan_empty')), findsOneWidget);
  });

  testWidgets('shows add button when canEdit', (tester) async {
    await tester.pumpWidget(buildWidget(canEdit: true));
    expect(find.byKey(const Key('treatment_plan_add_button')), findsOneWidget);
  });

  testWidgets('hides add button when canEdit is false', (tester) async {
    await tester.pumpWidget(buildWidget(canEdit: false));
    expect(find.byKey(const Key('treatment_plan_add_button')), findsNothing);
  });

  testWidgets('displays treatment plan cards', (tester) async {
    final plans = [
      const TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'visit-1',
        patientId: 'patient-1',
        medicationName: 'Amoxicillin',
        dosage: '500mg',
        frequency: 'twice daily',
      ),
    ];
    await tester.pumpWidget(buildWidget(plans: plans));
    expect(find.text('Amoxicillin'), findsOneWidget);
    expect(find.text('500mg · twice daily'), findsOneWidget);
  });

  testWidgets('tapping Add shows form', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treatment_plan_add_form')), findsOneWidget);
    expect(find.byKey(const Key('treatment_plan_medication_field')), findsOneWidget);
  });

  testWidgets('form validates required medication name', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('edit and archive buttons shown when canEdit', (tester) async {
    final plans = [
      const TreatmentPlanItem(id: 'tp-1', visitId: 'visit-1', patientId: 'patient-1', medicationName: 'Ibuprofen'),
    ];
    await tester.pumpWidget(buildWidget(plans: plans, canEdit: true));
    expect(find.byKey(const Key('treatment_plan_edit_tp-1')), findsOneWidget);
    expect(find.byKey(const Key('treatment_plan_archive_tp-1')), findsOneWidget);
  });

  testWidgets('edit and archive buttons hidden when canEdit is false', (tester) async {
    final plans = [
      const TreatmentPlanItem(id: 'tp-1', visitId: 'visit-1', patientId: 'patient-1', medicationName: 'Ibuprofen'),
    ];
    await tester.pumpWidget(buildWidget(plans: plans, canEdit: false));
    expect(find.byKey(const Key('treatment_plan_edit_tp-1')), findsNothing);
    expect(find.byKey(const Key('treatment_plan_archive_tp-1')), findsNothing);
  });

  testWidgets('shows duration text on card', (tester) async {
    final plans = [
      const TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'visit-1',
        patientId: 'patient-1',
        medicationName: 'Amoxicillin',
        duration: '7 days',
      ),
    ];
    await tester.pumpWidget(buildWidget(plans: plans));
    expect(find.textContaining('7 days'), findsOneWidget);
  });

  testWidgets('edit form sends empty string when optional dosage is cleared', (tester) async {
    final plans = [
      const TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'visit-1',
        patientId: 'patient-1',
        medicationName: 'Ibuprofen',
        dosage: '500mg',
      ),
    ];
    await tester.pumpWidget(buildWidget(plans: plans));
    await tester.tap(find.byKey(const Key('treatment_plan_edit_tp-1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('treatment_plan_dosage_field')), '');
    await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
    await tester.pumpAndSettle();

    final params = testClient.paramsForFunction('update_treatment_plan')!;
    expect(params['p_dosage'], '');
  });

  testWidgets('edit form sends only changed fields on update RPC', (tester) async {
    final plans = [
      const TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'visit-1',
        patientId: 'patient-1',
        medicationName: 'Ibuprofen',
        dosage: '500mg',
        frequency: 'BID',
        duration: '7 days',
      ),
    ];
    await tester.pumpWidget(buildWidget(plans: plans));
    await tester.tap(find.byKey(const Key('treatment_plan_edit_tp-1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('treatment_plan_duration_field')), '10 days');
    await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
    await tester.pumpAndSettle();

    final params = testClient.paramsForFunction('update_treatment_plan')!;
    expect(params['p_medication_name'], isNull);
    expect(params['p_dosage'], isNull);
    expect(params['p_frequency'], isNull);
    expect(params['p_duration'], '10 days');
    expect(params.containsKey('p_start_date'), isFalse);
    expect(params.containsKey('p_end_date'), isFalse);
  });

  testWidgets('edit form submits update RPC and calls onChanged', (tester) async {
    var changedCalled = false;
    final plans = [
      const TreatmentPlanItem(id: 'tp-1', visitId: 'visit-1', patientId: 'patient-1', medicationName: 'Ibuprofen'),
    ];
    await tester.pumpWidget(buildWidget(plans: plans, onChanged: () => changedCalled = true));
    await tester.tap(find.byKey(const Key('treatment_plan_edit_tp-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('treatment_plan_edit_form_tp-1')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('treatment_plan_medication_field')), 'Ibuprofen XR');
    await tester.enterText(find.byKey(const Key('treatment_plan_duration_field')), '5 days');
    await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
    await tester.pumpAndSettle();

    expect(changedCalled, isTrue);
    expect(testClient.rpcLog, contains('update_treatment_plan'));
    final params = testClient.paramsForFunction('update_treatment_plan')!;
    expect(params['p_medication_name'], 'Ibuprofen XR');
    expect(params['p_duration'], '5 days');
  });

  testWidgets('archive confirms then calls archive RPC', (tester) async {
    var changedCalled = false;
    final plans = [
      const TreatmentPlanItem(id: 'tp-1', visitId: 'visit-1', patientId: 'patient-1', medicationName: 'Ibuprofen'),
    ];
    await tester.pumpWidget(buildWidget(plans: plans, onChanged: () => changedCalled = true));
    await tester.tap(find.byKey(const Key('treatment_plan_archive_tp-1')));
    await tester.pumpAndSettle();

    expect(find.text('Remove treatment plan?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(changedCalled, isTrue);
    expect(testClient.rpcLog, contains('archive_treatment_plan'));
  });

  testWidgets('add form submits and calls onChanged', (tester) async {
    var changedCalled = false;
    await tester.pumpWidget(buildWidget(onChanged: () => changedCalled = true));
    await tester.tap(find.byKey(const Key('treatment_plan_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('treatment_plan_medication_field')), 'Aspirin');
    await tester.tap(find.byKey(const Key('treatment_plan_save_button')));
    await tester.pumpAndSettle();
    expect(changedCalled, isTrue);
    expect(testClient.rpcLog, contains('create_treatment_plan'));
  });
}
