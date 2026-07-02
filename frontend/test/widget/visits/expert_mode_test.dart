import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';
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
        child: Column(
          children: [
            const Align(alignment: Alignment.centerRight, child: EncounterWorkspaceModeToggle()),
            Expanded(
              child: EncounterWorkspaceShell(
                visitId: encounterTestVisitId,
                state: state,
                canEdit: true,
                canUploadAttachments: true,
                onRefresh: () {},
              ),
            ),
          ],
        ),
      );

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);

      await tester.tap(find.byKey(const Key('encounter_mode_expert')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_mode_transition')), findsOneWidget);
      expect(find.byKey(const Key('expert_mode_accordion')), findsOneWidget);

      await tester.tap(find.byKey(const Key('encounter_mode_guided')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
    });

    testWidgets('expert mode renders all documentation phase sections', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: Column(
          children: [
            const Align(alignment: Alignment.centerRight, child: EncounterWorkspaceModeToggle()),
            Expanded(
              child: EncounterWorkspaceShell(
                visitId: encounterTestVisitId,
                state: state,
                canEdit: true,
                canUploadAttachments: true,
                onRefresh: () {},
              ),
            ),
          ],
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
