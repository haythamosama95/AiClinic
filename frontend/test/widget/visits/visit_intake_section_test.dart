<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
=======
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/visit_encounter_draft.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_intake_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_medical_background_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_form_dialog.dart';

import 'visit_widget_test_harness.dart';

Future<StubVisitDocumentationNotifier> _pumpIntakeSection(
  WidgetTester tester, {
  required StubVisitDocumentationNotifier docNotifier,
  bool canEdit = true,
  PatientSafetyContext? patientSafety,
  bool patientSafetyLoading = false,
  Object? patientSafetyError,
  List<Override> extraOverrides = const [],
}) async {
  await pumpVisitsSurface(
    tester,
    child: SingleChildScrollView(
      child: VisitIntakeSection(visitId: encounterTestVisitId, canEdit: canEdit),
    ),
    overrides: visitsProviderOverrides(
      auth: visitsAuthSession(),
      visitId: encounterTestVisitId,
      docNotifier: docNotifier,
      patientId: encounterTestPatientId,
      patientSafety: patientSafety,
      patientSafetyLoading: patientSafetyLoading,
      patientSafetyError: patientSafetyError,
      extraOverrides: extraOverrides,
    ),
  );
  await pumpVisitsFrames(tester);
  await pumpVisitsFrames(tester);
  return docNotifier;
}

StubVisitDocumentationNotifier _docNotifier({VisitDocumentationState? state}) {
  return StubVisitDocumentationNotifier(
    encounterTestVisitId,
    state ?? sampleEncounterDocState(),
  );
}

AppRichTextEditor _richTextEditor(WidgetTester tester, String semanticsId) {
<<<<<<< HEAD
  final finder = find.descendant(
=======
  final finder = find.ancestor(
>>>>>>> master
    of: find.bySemanticsIdentifier(semanticsId),
    matching: find.byType(AppRichTextEditor),
  );
  expect(finder, findsOneWidget);
  return tester.widget<AppRichTextEditor>(finder);
}

void _driveRichText(WidgetTester tester, String semanticsId, String text) {
  final editor = _richTextEditor(tester, semanticsId);
  expect(editor.controller, isNotNull);
  setQuillControllerPlainText(editor.controller!, text);
}

Future<void> _submitMedicalBackgroundDialog(WidgetTester tester, {required String title, String? note}) async {
  final dialog = find.byType(MedicalBackgroundFormDialog);
  expect(dialog, findsOneWidget);
  final fields = find.descendant(of: dialog, matching: find.byType(EditableText));
  await tester.enterText(fields.at(0), title);
  if (note != null) {
    await tester.enterText(fields.at(1), note);
  }
<<<<<<< HEAD
  await tester.tap(find.widgetWithText(AppButton, 'Add'));
=======
  final submitButton = find.descendant(
    of: dialog,
    matching: find.widgetWithText(AppButton, 'Add'),
  );
  await tester.ensureVisible(submitButton);
  await tester.tap(submitButton);
>>>>>>> master
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitIntakeSection — build & structure', () {
    testWidgets('trivial: builds with administrator session and in-progress visit', (tester) async {
      await _pumpIntakeSection(tester, docNotifier: _docNotifier());

      expect(find.byType(VisitIntakeSection), findsOneWidget);
      expect(find.text('Patient intake'), findsOneWidget);
    });

    testWidgets('trivial: shows section heading, subtitle, and field labels', (tester) async {
      await _pumpIntakeSection(tester, docNotifier: _docNotifier());

      expect(find.text('Record the presenting complaint and relevant medical background.'), findsOneWidget);
      expect(find.text('Chief complaint'), findsOneWidget);
      expect(find.text('History of present illness'), findsOneWidget);
      expect(find.text('Medical background'), findsOneWidget);
      expect(
        find.text('Chronic conditions, allergies, and current medications relevant to this visit.'),
        findsOneWidget,
      );
    });

    testWidgets('trivial: contains rich-text editors and medical background editor', (tester) async {
      await _pumpIntakeSection(tester, docNotifier: _docNotifier());

      expect(find.bySemanticsIdentifier('chief-complaint-input'), findsOneWidget);
      expect(find.bySemanticsIdentifier('history-of-present-illness-input'), findsOneWidget);
      expect(find.byType(VisitMedicalBackgroundEditor), findsOneWidget);
      expect(find.text('Chronic conditions'), findsOneWidget);
      expect(find.text('Allergies'), findsOneWidget);
      expect(find.text('Current medications'), findsOneWidget);
    });
  });

  group('VisitIntakeSection — pre-populated & empty state', () {
    testWidgets('trivial: renders existing complaint and history from documentation state', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            complaint: 'Sore throat',
            history: 'Started 3 days ago with mild fever',
          ),
        ),
      );

<<<<<<< HEAD
      expect(find.text('Sore throat'), findsOneWidget);
      expect(find.textContaining('Started 3 days ago'), findsOneWidget);
=======
      expect(
        plainTextFromQuillDocument(_richTextEditor(tester, 'chief-complaint-input').controller!.document),
        'Sore throat',
      );
      expect(
        plainTextFromQuillDocument(_richTextEditor(tester, 'history-of-present-illness-input').controller!.document),
        'Started 3 days ago with mild fever',
      );
>>>>>>> master
    });

    testWidgets('trivial: empty patient safety shows nothing-documented copy in each category', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafety: buildPatientSafetyContext(),
      );

      expect(find.text('Nothing documented yet'), findsNWidgets(3));
    });

    testWidgets('trivial: patient safety provider data renders medical background entries', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafety: buildPatientSafetyContext(
          chronicConditions: [buildPatientChronicCondition(name: 'Type 2 diabetes')],
          allergies: [buildPatientAllergy(substance: 'Penicillin', reaction: 'Rash')],
          currentMedications: [buildPatientMedication(name: 'Metformin', note: '500 mg daily')],
        ),
      );

      expect(find.text('Type 2 diabetes'), findsOneWidget);
      expect(find.text('Penicillin'), findsOneWidget);
      expect(find.text('Rash'), findsOneWidget);
      expect(find.text('Metformin'), findsOneWidget);
      expect(find.text('500 mg daily'), findsOneWidget);
    });
  });

  group('VisitIntakeSection — read-only vs editable', () {
    testWidgets('trivial: canEdit false disables rich-text editors', (tester) async {
      await _pumpIntakeSection(tester, docNotifier: _docNotifier(), canEdit: false);

      final complaintSemantics = tester.getSemantics(find.bySemanticsIdentifier('chief-complaint-input'));
<<<<<<< HEAD
      expect(complaintSemantics.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
      expect(complaintSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);

      final historySemantics = tester.getSemantics(find.bySemanticsIdentifier('history-of-present-illness-input'));
      expect(historySemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
=======
      expect(complaintSemantics.flagsCollection.isEnabled, isNot(Tristate.none));
      expect(complaintSemantics.flagsCollection.isEnabled, Tristate.isFalse);

      final historySemantics = tester.getSemantics(find.bySemanticsIdentifier('history-of-present-illness-input'));
      expect(historySemantics.flagsCollection.isEnabled, Tristate.isFalse);
>>>>>>> master
    });

    testWidgets('trivial: canEdit false hides medical background add affordances', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafety: buildPatientSafetyContext(
          chronicConditions: [buildPatientChronicCondition()],
        ),
        canEdit: false,
      );

      expect(find.text('Add'), findsNothing);
      expect(find.bySemanticsLabel('Edit Type 2 diabetes'), findsNothing);
      expect(find.bySemanticsLabel('Remove Type 2 diabetes'), findsNothing);
    });

    testWidgets('advanced: canEdit true shows add affordances in empty medical background', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafety: buildPatientSafetyContext(),
        canEdit: true,
      );

      expect(find.text('Add'), findsNWidgets(3));
    });
  });

  group('VisitIntakeSection — rich-text notifier wiring', () {
    testWidgets('advanced: chief complaint change routes to updateComplaint', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(tester, docNotifier: notifier);

      _driveRichText(tester, 'chief-complaint-input', 'Persistent cough');
      await pumpVisitsFrames(tester);

      expect(notifier.updateComplaintCallCount, greaterThan(0));
      expect(notifier.lastUpdateComplaint, 'Persistent cough');
    });

    testWidgets('advanced: history change routes to updateHistory', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(tester, docNotifier: notifier);

      _driveRichText(tester, 'history-of-present-illness-input', 'Onset last Tuesday');
      await pumpVisitsFrames(tester);

      expect(notifier.updateHistoryCallCount, greaterThan(0));
      expect(notifier.lastUpdateHistory, 'Onset last Tuesday');
    });

    testWidgets('invalid state: read-only mode does not route rich-text changes to notifier', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(tester, docNotifier: notifier, canEdit: false);

      _driveRichText(tester, 'chief-complaint-input', 'Should not save');
      await pumpVisitsFrames(tester);

      expect(notifier.updateComplaintCallCount, 0);
      expect(notifier.updateHistoryCallCount, 0);
    });
  });

  group('VisitIntakeSection — medical background notifier wiring', () {
    testWidgets('advanced: create chronic condition routes to stageCreateCondition with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(),
      );

      await tester.tap(find.text('Add').first);
      await pumpVisitsFrames(tester);
      await _submitMedicalBackgroundDialog(tester, title: 'Asthma', note: 'Mild intermittent');

      expect(notifier.stageCreateConditionCallCount, 1);
      expect(notifier.lastStageCreateConditionName, 'Asthma');
      expect(notifier.lastStageCreateConditionNote, 'Mild intermittent');
    });

    testWidgets('advanced: create allergy routes to stageCreateAllergy with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(),
      );

      await tester.ensureVisible(find.text('Allergies'));
      await tester.tap(find.text('Add').at(1));
      await pumpVisitsFrames(tester);
      await _submitMedicalBackgroundDialog(tester, title: 'Shellfish', note: 'Hives');

      expect(notifier.stageCreateAllergyCallCount, 1);
      expect(notifier.lastStageCreateAllergySubstance, 'Shellfish');
      expect(notifier.lastStageCreateAllergyReaction, 'Hives');
    });

    testWidgets('advanced: archive chronic condition routes to stageArchiveCondition', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(
          chronicConditions: [buildPatientChronicCondition(name: 'Hypertension')],
        ),
      );

      await tester.tap(find.bySemanticsLabel('Remove Hypertension'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageArchiveConditionCallCount, 1);
      expect(notifier.lastStageArchiveConditionId, encounterTestConditionId);
    });

    testWidgets('advanced: edit chronic condition routes to stageUpdateCondition with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(
          chronicConditions: [buildPatientChronicCondition(name: 'Hypertension', note: 'Controlled')],
        ),
      );

      await tester.tap(find.bySemanticsLabel('Edit Hypertension'));
      await pumpVisitsFrames(tester);

      final dialog = find.byType(MedicalBackgroundFormDialog);
      final fields = find.descendant(of: dialog, matching: find.byType(EditableText));
      await tester.enterText(fields.at(0), 'Hypertension stage 1');
      await tester.enterText(fields.at(1), 'On lisinopril');
      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageUpdateConditionCallCount, 1);
      expect(notifier.lastStageUpdateConditionId, encounterTestConditionId);
      expect(notifier.lastStageUpdateConditionName, 'Hypertension stage 1');
      expect(notifier.lastStageUpdateConditionNote, 'On lisinopril');
    });

    testWidgets('advanced: create medication routes to stageCreateMedication with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(),
      );

      await tester.ensureVisible(find.text('Current medications'));
      await tester.tap(find.text('Add').last);
      await pumpVisitsFrames(tester);
      await _submitMedicalBackgroundDialog(tester, title: 'Lisinopril', note: '10 mg daily');

      expect(notifier.stageCreateMedicationCallCount, 1);
      expect(notifier.lastStageCreateMedicationName, 'Lisinopril');
      expect(notifier.lastStageCreateMedicationNote, '10 mg daily');
    });

    testWidgets('advanced: archive allergy routes to stageArchiveAllergy', (tester) async {
      final notifier = _docNotifier();
      await _pumpIntakeSection(
        tester,
        docNotifier: notifier,
        patientSafety: buildPatientSafetyContext(
          allergies: [buildPatientAllergy(substance: 'Latex')],
        ),
      );

      await tester.tap(find.bySemanticsLabel('Remove Latex'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageArchiveAllergyCallCount, 1);
      expect(notifier.lastStageArchiveAllergyId, encounterTestAllergyId);
    });
  });

  group('VisitIntakeSection — patient safety provider states', () {
    testWidgets('edge case: loading patient safety still builds with empty medical background', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafetyLoading: true,
      );

      expect(find.byType(VisitMedicalBackgroundEditor), findsOneWidget);
      expect(find.text('Nothing documented yet'), findsNWidgets(3));
    });

    testWidgets('edge case: patient safety error still builds with empty medical background', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(),
        patientSafetyError: Exception('patient safety RPC failed'),
      );

      expect(find.byType(VisitMedicalBackgroundEditor), findsOneWidget);
      expect(find.text('Nothing documented yet'), findsNWidgets(3));
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('edge case: encounter draft patient safety merges over provider context', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            encounterDraft: buildVisitEncounterDraft(
              patientSafety: const PatientSafetyDraft(
                pendingConditions: [
                  PatientChronicCondition(id: 'draft-condition-id', name: 'Draft asthma'),
                ],
              ),
            ),
          ),
        ),
        patientSafety: buildPatientSafetyContext(
          chronicConditions: [buildPatientChronicCondition(name: 'Type 2 diabetes')],
        ),
      );

      expect(find.text('Draft asthma'), findsOneWidget);
      expect(find.text('Type 2 diabetes'), findsOneWidget);
    });
  });

  group('VisitIntakeSection — saveStatus and errorMessage (not rendered here)', () {
    testWidgets('regression: saveStatus and errorMessage in state do not surface in this section', (tester) async {
      await _pumpIntakeSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            saveStatus: DocumentationSaveStatus.error,
            errorMessage: 'Save failed: network timeout',
          ),
        ),
      );

      expect(find.textContaining('Save failed'), findsNothing);
      expect(find.textContaining('Saving'), findsNothing);
      expect(find.textContaining('Saved'), findsNothing);
    });
  });
}
