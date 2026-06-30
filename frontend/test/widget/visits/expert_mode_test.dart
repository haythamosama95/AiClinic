import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visit_encounter_test_support.dart';

void main() {
  group('expert mode', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('toggle preserves draft content across guided and expert modes', (tester) async {
      final state = sampleEncounterDocState().copyWith(complaint: 'Persistent headache');

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: EncounterWorkspaceShell(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_step_subjective')));
      await tester.pumpAndSettle();
      expect(find.text('Persistent headache'), findsOneWidget);

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expert_mode_accordion')), findsOneWidget);
      expect(find.text('Persistent headache'), findsOneWidget);

      await tester.tap(find.byKey(const Key('encounter_mode_guided')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('encounter_step_subjective')));
      await tester.pumpAndSettle();
      expect(find.text('Persistent headache'), findsOneWidget);
    });

    testWidgets('expert mode renders all five phase sections', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: EncounterWorkspaceShell(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();

      for (final phase in EncounterPhase.documentationPhases) {
        expect(find.byKey(Key('expert_mode_phase_${phase.name}')), findsOneWidget);
      }
    });
  });
}
