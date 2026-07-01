import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visit_encounter_test_support.dart';

class _GuidedEncounterWorkspace extends StatelessWidget {
  const _GuidedEncounterWorkspace({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    required this.onRefresh,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterJoinedHeader(visitId: visitId, visit: state.visit, onBack: () {}),
        const SizedBox(height: 16),
        Expanded(
          child: EncounterWorkspaceShell(
            visitId: visitId,
            state: state,
            canEdit: canEdit,
            canUploadAttachments: canUploadAttachments,
            onRefresh: onRefresh,
          ),
        ),
      ],
    );
  }
}

void main() {
  group('encounter workspace shell', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('guided mode shows only the active phase canvas', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      expect(find.byKey(const Key('encounter_workspace_shell')), findsOneWidget);
      expect(find.byKey(const Key('encounter_stepper')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_sticky_footer')), findsNothing);
    });

    testWidgets('non-linear navigation jumps from subjective to plan', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_step_plan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_plan')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);
    });

    testWidgets('step badges reflect draft content', (tester) async {
      final visit = sampleEncounterVisit(visitType: 'Follow-up');
      final state = sampleEncounterDocState(visit: visit).copyWith(complaint: 'Headache');

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    });

    testWidgets('review step shows summary and hides documentation phases', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: _GuidedEncounterWorkspace(
          visitId: encounterTestVisitId,
          state: state,
          canEdit: true,
          canUploadAttachments: true,
          onRefresh: () {},
        ),
      );

      await tester.tap(find.byKey(const Key('encounter_step_review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);
    });
  });
}
