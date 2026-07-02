import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
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

Widget _finishVisitTrailing() {
  return Builder(
    builder: (context) {
      return TextButton(
        key: const Key('visit_finish_button'),
        onPressed: () {
          ProviderScope.containerOf(context)
              .read(encounterActivePhaseProvider(encounterTestVisitId).notifier)
              .setPhase(EncounterPhase.review);
        },
        child: const Text('Finish Visit'),
      );
    },
  );
}

Finder _workspaceFadeTransition() {
  return find.byWidgetPredicate((widget) => widget is FadeTransition && widget.child is IgnorePointer);
}

Future<void> _pumpGuidedWorkspace(WidgetTester tester, {Widget? trailing}) async {
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
      trailing: trailing,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FE-004 — Summary fade transition', () {
    testWidgets('AppPageFadeTransition fades from documentation to EncounterReview', (tester) async {
      await _pumpGuidedWorkspace(tester, trailing: _finishVisitTrailing());

      expect(find.byKey(const Key('encounter_workspace_transition')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_review')), findsNothing);

      await tester.tap(find.byKey(const Key('visit_finish_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final midFade = tester.widget<FadeTransition>(_workspaceFadeTransition());
      expect(midFade.opacity.value, lessThan(1));

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_review')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);

      final settledFade = tester.widget<FadeTransition>(_workspaceFadeTransition());
      expect(settledFade.opacity.value, 1);
    });
  });

  group('EDGE-004 — Rapid step switching during fade transition', () {
    testWidgets('Summary then Intake during fade leaves Intake visible without crash', (tester) async {
      await _pumpGuidedWorkspace(tester, trailing: _finishVisitTrailing());

      await tester.tap(find.byKey(const Key('visit_finish_button')));
      await tester.tap(find.byKey(const Key('encounter_step_subjective')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);
      expect(find.byKey(const Key('encounter_review')), findsNothing);

      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.subjective);
    });
  });
}
