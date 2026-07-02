import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    this.trailing,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterJoinedHeader(visitId: visitId, visit: state.visit, onBack: () {}, trailing: trailing),
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
      expect(find.byKey(const Key('encounter_phase_page_transition')), findsOneWidget);
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

    testWidgets('guided stepper excludes summary step', (tester) async {
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

      expect(find.byKey(const Key('encounter_step_subjective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_step_objective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_step_plan')), findsOneWidget);
      expect(find.byKey(const Key('encounter_step_review')), findsNothing);
    });

    testWidgets('finish visit shows summary and hides documentation phases', (tester) async {
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
          trailing: Builder(
            builder: (context) {
              return TextButton(
                key: const Key('visit_finish_button'),
                onPressed: () {
                  final container = ProviderScope.containerOf(context);
                  container
                      .read(encounterActivePhaseProvider(encounterTestVisitId).notifier)
                      .setPhase(EncounterPhase.review);
                },
                child: const Text('Finish Visit'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('visit_finish_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);
      expect(find.byKey(const Key('encounter_workspace_transition')), findsOneWidget);
    });

    testWidgets('summary edit in expert mode returns to expert accordion', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: const Size(1280, 900),
        scrollable: false,
        child: Column(
          children: [
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

      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
      await container.read(workspaceModeProvider.notifier).setMode(WorkspaceMode.expert);
      await tester.pumpAndSettle();

      container.read(encounterActivePhaseProvider(encounterTestVisitId).notifier).setPhase(EncounterPhase.review);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);

      await tester.tap(find.byKey(const Key('encounter_review_edit_plan')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsNothing);
      expect(find.byKey(const Key('expert_mode_accordion')), findsOneWidget);
      expect(find.byKey(const Key('expert_mode_phase_plan')), findsOneWidget);
    });
  });
}
