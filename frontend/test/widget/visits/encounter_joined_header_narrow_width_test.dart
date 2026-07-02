import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visit_encounter_test_support.dart';

const _narrowViewport = Size(1024, 768);

class _JoinedHeaderHarness extends StatelessWidget {
  const _JoinedHeaderHarness({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context) {
    return EncounterJoinedHeader(visitId: visitId, visit: state.visit, onBack: () {});
  }
}

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
  group('FE-007 — joined header at narrow width', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders at 1024×768 without layout overflow', (tester) async {
      final errors = <Object>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exception);
      addTearDown(() => FlutterError.onError = old);

      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: _narrowViewport,
        scrollable: false,
        child: _JoinedHeaderHarness(visitId: encounterTestVisitId, state: state),
      );

      expect(tester.takeException(), isNull);
      expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
      expect(find.byKey(const Key('encounter_header')), findsOneWidget);
      expect(find.byKey(const Key('encounter_stepper')), findsOneWidget);
    });

    testWidgets('keeps stepper aligned within joined header bounds', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        size: _narrowViewport,
        scrollable: false,
        child: _JoinedHeaderHarness(visitId: encounterTestVisitId, state: state),
      );

      final headerRect = tester.getRect(find.byKey(const Key('encounter_header')));
      final stepperRect = tester.getRect(find.byKey(const Key('encounter_stepper')));

      expect(stepperRect.top, greaterThan(headerRect.top));
      expect(stepperRect.left, greaterThanOrEqualTo(headerRect.left));
      expect(stepperRect.right, lessThanOrEqualTo(headerRect.right));
      expect(stepperRect.bottom, lessThanOrEqualTo(headerRect.bottom));
    });

    testWidgets('stepper remains usable for non-linear phase navigation', (tester) async {
      final state = sampleEncounterDocState();

      await pumpEncounterWidget(
        tester,
        docState: state,
        // Keep narrow width; extra height avoids unrelated workspace overflow
        // while exercising stepper taps with the full guided shell.
        size: const Size(1024, 900),
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

      await tester.tap(find.byKey(const Key('encounter_step_plan')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('encounter_phase_plan')), findsOneWidget);
      expect(find.byKey(const Key('encounter_phase_subjective')), findsNothing);
    });
  });
}
