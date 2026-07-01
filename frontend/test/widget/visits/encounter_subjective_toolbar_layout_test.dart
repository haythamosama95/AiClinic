import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visit_encounter_test_support.dart';

void main() {
  testWidgets('subjective rich text toolbar lays out with bounded height', (tester) async {
    final state = sampleEncounterDocState();

    await pumpEncounterWidget(
      tester,
      docState: state,
      scrollable: false,
      size: const Size(900, 700),
      child: EncounterPhaseSubjective(visitId: encounterTestVisitId, state: state, canEdit: true),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Complaint'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
