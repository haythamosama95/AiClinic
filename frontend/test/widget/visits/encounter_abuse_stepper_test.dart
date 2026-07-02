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

Key _stepKey(EncounterPhase phase) => Key('encounter_step_${phase.name}');

Key _phaseKey(EncounterPhase phase) => Key('encounter_phase_${phase.name}');

Future<void> _pumpGuidedWorkspace(WidgetTester tester, VisitDocumentationState state) {
  return pumpEncounterWidget(
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
}

Future<void> _rapidTapSteps(WidgetTester tester, List<EncounterPhase> phases) async {
  for (final phase in phases) {
    await tester.tap(find.byKey(_stepKey(phase)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void _expectActivePhase(WidgetTester tester, EncounterPhase phase) {
  expect(tester.takeException(), isNull);
  expect(find.byKey(_phaseKey(phase)), findsOneWidget);
  for (final other in EncounterPhase.stepperPhases) {
    if (other != phase) {
      expect(find.byKey(_phaseKey(other)), findsNothing);
    }
  }
}

void main() {
  group('ABUSE-004 — Rapid stepper clicks', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('rapid random order clicks end on last selected phase without exception', (tester) async {
      final errors = <Object>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = old);

      final state = sampleEncounterDocState();
      await _pumpGuidedWorkspace(tester, state);

      expect(find.byKey(const Key('encounter_stepper')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsOneWidget);

      const sequence = <EncounterPhase>[
        EncounterPhase.plan,
        EncounterPhase.subjective,
        EncounterPhase.objective,
        EncounterPhase.plan,
      ];
      await _rapidTapSteps(tester, sequence);

      final lastPhase = sequence.last;
      _expectActivePhase(tester, lastPhase);

      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), lastPhase);
      expect(errors, isEmpty);
    });

    testWidgets('rapid clicks ending on each stepper phase stay consistent', (tester) async {
      final sequences = <List<EncounterPhase>>[
        [EncounterPhase.objective, EncounterPhase.plan, EncounterPhase.subjective, EncounterPhase.objective],
        [EncounterPhase.plan, EncounterPhase.objective, EncounterPhase.subjective, EncounterPhase.subjective],
        [EncounterPhase.subjective, EncounterPhase.plan, EncounterPhase.objective, EncounterPhase.plan],
      ];

      for (final sequence in sequences) {
        final state = sampleEncounterDocState();
        await _pumpGuidedWorkspace(tester, state);
        await _rapidTapSteps(tester, sequence);

        final lastPhase = sequence.last;
        _expectActivePhase(tester, lastPhase);

        final container =
            ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
        expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), lastPhase);
      }
    });

    testWidgets('rapid repeated taps on one step then jump does not throw', (tester) async {
      final state = sampleEncounterDocState();
      await _pumpGuidedWorkspace(tester, state);

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(_stepKey(EncounterPhase.subjective)));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.tap(find.byKey(_stepKey(EncounterPhase.plan)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      _expectActivePhase(tester, EncounterPhase.plan);

      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('encounter_workspace_shell'))));
      expect(container.read(encounterActivePhaseProvider(encounterTestVisitId)), EncounterPhase.plan);
    });
  });
}
