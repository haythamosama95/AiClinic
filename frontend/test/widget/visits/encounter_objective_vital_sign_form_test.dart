import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

void main() {
  testWidgets('empty vital signs card shows centered add button only', (tester) async {
    final visit = sampleEncounterVisit();
    final state = sampleEncounterDocState(visit: visit).copyWith(
      predefinedVitalSigns: const [CatalogItem(id: 'bp-id', name: 'Blood Pressure', defaultUnit: 'mmHg')],
    );

    await pumpEncounterWidget(
      tester,
      docState: state,
      scrollable: false,
      size: const Size(1280, 900),
      child: EncounterPhaseObjective(visitId: encounterTestVisitId, state: state, canEdit: true, onRefresh: () {}),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vital_sign_add_button')), findsOneWidget);
    expect(find.byKey(const Key('vital_sign_empty')), findsOneWidget);
    expect(find.byKey(const Key('vital_sign_quick_add')), findsNothing);
  });

  testWidgets('objective vital sign add dialog opens from add button', (tester) async {
    final visit = sampleEncounterVisit();
    final state = sampleEncounterDocState(visit: visit).copyWith(
      predefinedVitalSigns: const [CatalogItem(id: 'bp-id', name: 'Blood Pressure', defaultUnit: 'mmHg')],
    );

    await pumpEncounterWidget(
      tester,
      docState: state,
      scrollable: false,
      size: const Size(1280, 900),
      child: EncounterPhaseObjective(visitId: encounterTestVisitId, state: state, canEdit: true, onRefresh: () {}),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vital_sign_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vital_sign_add_form')), findsOneWidget);
    expect(find.byKey(const Key('vital_sign_predefined_select')), findsOneWidget);
    expect(find.byKey(const Key('vital_sign_measured_at_date')), findsNothing);
    expect(find.byKey(const Key('vital_sign_measured_at_time')), findsNothing);
  });

  testWidgets('add form offers custom vital sign option in catalog select', (tester) async {
    final visit = sampleEncounterVisit();
    final state = sampleEncounterDocState(visit: visit).copyWith(
      predefinedVitalSigns: const [CatalogItem(id: 'bp-id', name: 'Blood Pressure', defaultUnit: 'mmHg')],
    );

    await pumpEncounterWidget(
      tester,
      docState: state,
      child: VitalSignList(
        visitId: encounterTestVisitId,
        vitalSigns: const [],
        predefinedVitalSigns: state.predefinedVitalSigns,
        canEdit: true,
        onChanged: () {},
        sectionTitle: 'Vital signs',
        sectionKind: VisitPanelKind.vitalSigns,
        embeddedInTrackingCard: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vital_sign_add_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vital_sign_predefined_select')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vital_sign_predefined_select')));
    await tester.pumpAndSettle();
    expect(find.text('Custom…'), findsOneWidget);
  });
}
