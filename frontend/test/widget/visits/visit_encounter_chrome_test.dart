import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_rich_text_editor.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_content.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_placeholder.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_encounter_step_rail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_findings_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_intake_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_summary_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_section.dart';

import 'visit_widget_test_harness.dart';

Future<void> _pumpChromeSurface(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
}) async {
  await pumpVisitsSurface(
    tester,
    child: child,
    overrides: overrides,
  );
  await pumpVisitsFrames(tester);
}

List<Override> _docOverrides() {
  return visitsProviderOverrides(
    visitId: encounterTestVisitId,
    patientId: encounterTestPatientId,
    docState: sampleEncounterDocState(),
  );
}

void main() {
  group('VisitEncounterHeader', () {
    testWidgets('trivial: renders patient identity', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterHeader(
          patientName: 'Jane Doe',
          patientAgeLabel: '42 years',
          currentPhase: EncounterPhase.subjective,
        ),
      );

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('42 years'), findsOneWidget);
    });

    testWidgets('trivial: hosts the encounter step rail', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterHeader(
          patientName: 'Jane Doe',
          currentPhase: EncounterPhase.objective,
        ),
      );

      expect(find.byType(VisitEncounterStepRail), findsOneWidget);
      expect(find.bySemanticsLabel('Visit progress'), findsOneWidget);
    });

    testWidgets('advanced: forwards onPhaseSelected from the embedded step rail', (tester) async {
      EncounterPhase? selected;
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterHeader(
          patientName: 'Jane Doe',
          currentPhase: EncounterPhase.subjective,
          onPhaseSelected: (phase) => selected = phase,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Treatment'));
      await pumpVisitsFrames(tester);

      expect(selected, EncounterPhase.plan);
    });
  });

  group('VisitEncounterStepRail', () {
    testWidgets('trivial: renders every stepper phase with production labels', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterStepRail(currentPhase: EncounterPhase.subjective),
      );

      for (final phase in EncounterPhase.stepperPhases) {
        expect(find.text(phase.label), findsOneWidget);
      }
    });

    testWidgets('advanced: marks the current phase as selected in semantics', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterStepRail(currentPhase: EncounterPhase.objective),
      );

      final intakeSemantics = tester.getSemantics(find.bySemanticsLabel('Intake'));
      final findingsSemantics = tester.getSemantics(find.bySemanticsLabel('Findings & Diagnosis'));
      final treatmentSemantics = tester.getSemantics(find.bySemanticsLabel('Treatment'));

      expect(intakeSemantics.flagsCollection.isSelected, isNot(Tristate.isTrue));
      expect(findingsSemantics.flagsCollection.isSelected, Tristate.isTrue);
      expect(treatmentSemantics.flagsCollection.isSelected, isNot(Tristate.isTrue));
    });

    testWidgets('advanced: tapping a step invokes onPhaseSelected with that phase', (tester) async {
      EncounterPhase? selected;
      await _pumpChromeSurface(
        tester,
        child: VisitEncounterStepRail(
          currentPhase: EncounterPhase.subjective,
          onPhaseSelected: (phase) => selected = phase,
        ),
      );

      await tester.tap(find.bySemanticsLabel('Findings & Diagnosis'));
      await pumpVisitsFrames(tester);

      expect(selected, EncounterPhase.objective);
    });

    testWidgets('edge case: rail without onPhaseSelected still renders tappable semantics', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: const VisitEncounterStepRail(currentPhase: EncounterPhase.plan),
      );

      expect(find.bySemanticsLabel('Intake'), findsOneWidget);
      expect(find.bySemanticsLabel('Findings & Diagnosis'), findsOneWidget);
      expect(find.bySemanticsLabel('Treatment'), findsOneWidget);
    });
  });

  group('VisitEncounterStepContent', () {
    for (final phase in EncounterPhase.values) {
      testWidgets('regression: routes ${phase.name} to the expected child widget', (tester) async {
        await _pumpChromeSurface(
          tester,
          child: VisitEncounterStepContent(
            visitId: encounterTestVisitId,
            phase: phase,
            canEdit: true,
          ),
          overrides: _docOverrides(),
        );

        switch (phase) {
          case EncounterPhase.subjective:
            expect(find.byType(VisitIntakeSection), findsOneWidget);
          case EncounterPhase.objective:
            expect(find.byType(VisitFindingsSection), findsOneWidget);
          case EncounterPhase.plan:
            expect(find.byType(VisitTreatmentSection), findsOneWidget);
          case EncounterPhase.review:
            expect(find.byType(VisitSummarySection), findsOneWidget);
          case EncounterPhase.billing:
          case EncounterPhase.context:
            expect(find.byType(VisitEncounterStepPlaceholder), findsOneWidget);
        }
      });
    }

    testWidgets('advanced: canEdit false keeps intake editors read-only', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: const VisitEncounterStepContent(
          visitId: encounterTestVisitId,
          phase: EncounterPhase.subjective,
          canEdit: false,
        ),
        overrides: _docOverrides(),
      );

      final editors = tester.widgetList<AppRichTextEditor>(find.byType(AppRichTextEditor));
      expect(editors, isNotEmpty);
      expect(editors.every((editor) => editor.readOnly), isTrue);
      expect(editors.every((editor) => editor.disabled), isTrue);
    });

    testWidgets('advanced: canEdit true keeps intake editors editable', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: const VisitEncounterStepContent(
          visitId: encounterTestVisitId,
          phase: EncounterPhase.subjective,
          canEdit: true,
        ),
        overrides: _docOverrides(),
      );

      final editors = tester.widgetList<AppRichTextEditor>(find.byType(AppRichTextEditor));
      expect(editors, isNotEmpty);
      expect(editors.every((editor) => !editor.readOnly), isTrue);
      expect(editors.every((editor) => !editor.disabled), isTrue);
    });
  });

  group('VisitEncounterStepPlaceholder', () {
    testWidgets('trivial: billing phase renders billing placeholder copy', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: const VisitEncounterStepPlaceholder(phase: EncounterPhase.billing),
      );

      expect(find.text('Billing'), findsOneWidget);
      expect(
        find.text('Select services, review charges, and finalize the invoice for this visit.'),
        findsOneWidget,
      );
    });

    testWidgets('trivial: context phase renders summary placeholder copy', (tester) async {
      await _pumpChromeSurface(
        tester,
        child: const VisitEncounterStepPlaceholder(phase: EncounterPhase.context),
      );

      expect(find.text('Summary'), findsOneWidget);
      expect(
        find.text('Review the completed encounter before finishing the visit.'),
        findsOneWidget,
      );
    });

    testWidgets('advanced: every EncounterPhase value builds without throwing', (tester) async {
      for (final phase in EncounterPhase.values) {
        await _pumpChromeSurface(
          tester,
          child: VisitEncounterStepPlaceholder(phase: phase),
        );

        switch (phase) {
          case EncounterPhase.subjective:
            expect(find.text('Intake'), findsOneWidget);
            expect(
              find.text('Record the patient complaint, history, and safety context for this visit.'),
              findsOneWidget,
            );
          case EncounterPhase.objective:
            expect(find.text('Findings & diagnosis'), findsOneWidget);
            expect(
              find.text('Document examination findings, vitals, investigations, and diagnosis.'),
              findsOneWidget,
            );
          case EncounterPhase.plan:
            expect(find.text('Treatment'), findsOneWidget);
            expect(
              find.text('Plan treatment, prescriptions, follow-up, and visit attachments.'),
              findsOneWidget,
            );
          case EncounterPhase.context:
          case EncounterPhase.review:
            expect(find.text('Summary'), findsOneWidget);
            expect(
              find.text('Review the completed encounter before finishing the visit.'),
              findsOneWidget,
            );
          case EncounterPhase.billing:
            expect(find.text('Billing'), findsOneWidget);
            expect(
              find.text('Select services, review charges, and finalize the invoice for this visit.'),
              findsOneWidget,
            );
        }
      }
    });
  });

  group('VisitEncounterStepRail — exhaustive phase coverage', () {
    testWidgets('regression: every EncounterPhase value is accounted for by chrome widgets', (tester) async {
      for (final phase in EncounterPhase.values) {
        if (EncounterPhase.stepperPhases.contains(phase)) {
          await _pumpChromeSurface(
            tester,
            child: VisitEncounterStepRail(currentPhase: phase),
          );
          expect(find.text(phase.label), findsOneWidget);
        } else {
          await _pumpChromeSurface(
            tester,
            child: VisitEncounterStepContent(
              visitId: encounterTestVisitId,
              phase: phase,
              canEdit: true,
            ),
            overrides: _docOverrides(),
          );
          if (phase == EncounterPhase.review) {
            expect(find.byType(VisitSummarySection), findsOneWidget);
          } else {
            expect(find.byType(VisitEncounterStepPlaceholder), findsOneWidget);
          }
        }
      }
    });
  });
}
