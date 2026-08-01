<<<<<<< HEAD
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
=======
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachments_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_investigations_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_plan_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_section.dart';

import 'visit_widget_test_harness.dart';

Future<StubVisitDocumentationNotifier> _pumpTreatmentSection(
  WidgetTester tester, {
  required StubVisitDocumentationNotifier docNotifier,
  bool canEdit = true,
}) async {
  await pumpVisitsSurface(
    tester,
    child: SingleChildScrollView(
      child: VisitTreatmentSection(visitId: encounterTestVisitId, canEdit: canEdit),
    ),
    overrides: visitsProviderOverrides(
      auth: visitsAuthSession(),
      visitId: encounterTestVisitId,
      docNotifier: docNotifier,
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

<<<<<<< HEAD
void _driveRichText(WidgetTester tester, String semanticsId, String text) {
  final finder = find.descendant(
=======
AppRichTextEditor _richTextEditor(WidgetTester tester, String semanticsId) {
  final finder = find.ancestor(
>>>>>>> master
    of: find.bySemanticsIdentifier(semanticsId),
    matching: find.byType(AppRichTextEditor),
  );
  expect(finder, findsOneWidget);
<<<<<<< HEAD
  final editor = tester.widget<AppRichTextEditor>(finder);
=======
  return tester.widget<AppRichTextEditor>(finder);
}

void _driveRichText(WidgetTester tester, String semanticsId, String text) {
  final editor = _richTextEditor(tester, semanticsId);
>>>>>>> master
  expect(editor.controller, isNotNull);
  setQuillControllerPlainText(editor.controller!, text);
}

<<<<<<< HEAD
Future<void> _tapSelectOption(WidgetTester tester, String semanticsId, String optionLabel) async {
  await tester.tap(find.bySemanticsIdentifier(semanticsId));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
}

Future<void> _selectComboboxOption(WidgetTester tester, String semanticsId, String query, String optionLabel) async {
  final combobox = find.bySemanticsIdentifier(semanticsId);
  await tester.tap(combobox);
  await tester.pump();
  await tester.enterText(combobox, query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
=======
Future<void> _scrollTargetIntoView(WidgetTester tester, Finder target) async {
  final scrollable = find.ancestor(of: target, matching: find.byType(Scrollable));
  if (scrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(target, 50, scrollable: scrollable.first);
    await tester.pump();
  }
  await tester.ensureVisible(target);
}

Future<void> _tapSelectOption(
  WidgetTester tester,
  String semanticsId,
  String optionLabel, {
  Finder? scope,
}) async {
  final select = scope == null
      ? find.bySemanticsIdentifier(semanticsId)
      : find.descendant(of: scope, matching: find.bySemanticsIdentifier(semanticsId));
  await _scrollTargetIntoView(tester, select);
  await tester.tap(select);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  final option = find.text(optionLabel).last;
  final overlayScrollable = find.descendant(
    of: find.byType(Overlay),
    matching: find.byType(Scrollable),
  );
  if (overlayScrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(option, 50, scrollable: overlayScrollable.last);
    await tester.pump();
  }
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
}

Future<void> _selectComboboxOption(
  WidgetTester tester,
  String semanticsId,
  String query,
  String optionLabel, {
  Finder? scope,
}) async {
  final combobox = scope == null
      ? find.bySemanticsIdentifier(semanticsId)
      : find.descendant(of: scope, matching: find.bySemanticsIdentifier(semanticsId));
  final field = find.descendant(
    of: combobox,
    matching: find.byType(TextField),
  );
  await _scrollTargetIntoView(tester, field);
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  final option = find.text(optionLabel).last;
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
>>>>>>> master
}

Future<void> _submitTreatmentPlanDialog(
  WidgetTester tester, {
  required String medicationQuery,
  required String dosage,
  required String frequencyLabel,
  required String durationLabel,
  String submitLabel = 'Add prescription',
}) async {
  final dialog = find.byType(TreatmentPlanFormDialog);
  expect(dialog, findsOneWidget);

<<<<<<< HEAD
  await _selectComboboxOption(tester, 'treatment-medication', medicationQuery, 'Amoxicillin');
  final dosageField = find.descendant(
    of: find.ancestor(of: find.text('Dosage'), matching: find.byType(AppFormField)),
    matching: find.byType(EditableText),
  );
  await tester.enterText(dosageField, dosage);
  await _tapSelectOption(tester, 'treatment-frequency-select', frequencyLabel);
  await _tapSelectOption(tester, 'treatment-duration-select', durationLabel);
  await tester.tap(find.widgetWithText(AppButton, submitLabel));
=======
  await _selectComboboxOption(
    tester,
    'treatment-medication',
    medicationQuery,
    'Amoxicillin',
    scope: dialog,
  );
  final dosageField = find.descendant(
    of: dialog,
    matching: find.descendant(
      of: find.ancestor(of: find.text('Dosage'), matching: find.byType(AppFormField)),
      matching: find.byType(EditableText),
    ),
  );
  await tester.enterText(dosageField, dosage);
  await _tapSelectOption(tester, 'treatment-frequency-select', frequencyLabel, scope: dialog);
  await _tapSelectOption(tester, 'treatment-duration-select', durationLabel, scope: dialog);
  final submitButton = find.descendant(
    of: dialog,
    matching: find.widgetWithText(AppButton, submitLabel),
  );
  await _scrollTargetIntoView(tester, submitButton);
  await tester.tap(submitButton);
>>>>>>> master
  await pumpVisitsFrames(tester);
}

Future<void> _submitInvestigationDialog(
  WidgetTester tester, {
  required String investigationQuery,
  String? note,
  String submitLabel = 'Add investigation',
}) async {
  final dialog = find.byType(InvestigationFormDialog);
  expect(dialog, findsOneWidget);

  await _selectComboboxOption(tester, 'investigation-type', investigationQuery, 'Complete Blood Count');
  if (note != null) {
    final noteField = find.descendant(
<<<<<<< HEAD
      of: find.ancestor(of: find.text('Clinical note'), matching: find.byType(AppFormField)),
      matching: find.byType(EditableText),
    );
    await tester.enterText(noteField, note);
  }
  await tester.tap(find.widgetWithText(AppButton, submitLabel));
=======
      of: dialog,
      matching: find.byType(TextField),
    ).last;
    await tester.enterText(noteField, note);
  }
  final submitButton = find.descendant(
    of: dialog,
    matching: find.widgetWithText(AppButton, submitLabel),
  );
  await _scrollTargetIntoView(tester, submitButton);
  await tester.tap(submitButton);
>>>>>>> master
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitTreatmentSection — build & structure', () {
    testWidgets('trivial: builds with administrator session and in-progress visit', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier());

      expect(find.byType(VisitTreatmentSection), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
    });

    testWidgets('trivial: shows section heading, subtitle, and field labels', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier());

      expect(find.text('Plan investigations, prescribe treatments, and attach supporting documents.'), findsOneWidget);
      expect(find.text('Treatment notes'), findsOneWidget);
      expect(find.text('Treatment plan'), findsOneWidget);
      expect(find.text('Investigations needed'), findsOneWidget);
      expect(find.text('Attachments'), findsOneWidget);
      expect(
        find.text('Add each prescription via the dialog with dosage, frequency, and duration.'),
        findsOneWidget,
      );
      expect(find.text('Add each test via the dialog with any relevant clinical notes.'), findsOneWidget);
      expect(find.text('Upload lab results, referrals, or other visit documents.'), findsOneWidget);
    });

    testWidgets('trivial: contains rich-text editor and structured editors', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier());

      expect(find.bySemanticsIdentifier('treatment-notes-input'), findsOneWidget);
      expect(find.byType(VisitTreatmentPlanEditor), findsOneWidget);
      expect(find.byType(VisitInvestigationsEditor), findsOneWidget);
      expect(find.byType(VisitAttachmentsEditor), findsOneWidget);
      expect(find.text('Prescriptions'), findsOneWidget);
      expect(find.text('Ordered investigations'), findsOneWidget);
      expect(find.bySemanticsIdentifier('visit-attachments'), findsOneWidget);
    });
  });

  group('VisitTreatmentSection — pre-populated & empty state', () {
    testWidgets('trivial: renders existing treatment notes', (tester) async {
      await _pumpTreatmentSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(plan: 'Rest and fluids for 5 days'),
        ),
      );

<<<<<<< HEAD
      expect(find.textContaining('Rest and fluids'), findsOneWidget);
=======
      expect(
        plainTextFromQuillDocument(_richTextEditor(tester, 'treatment-notes-input').controller!.document),
        contains('Rest and fluids'),
      );
>>>>>>> master
    });

    testWidgets('trivial: renders existing prescriptions, investigations, and attachments', (tester) async {
      await _pumpTreatmentSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            visit: sampleEncounterVisit(
              treatmentPlans: [
                buildVisitTreatmentPlanItem(
                  medicationName: 'Amoxicillin',
                  dosage: '500 mg',
                  frequency: 'bd',
                  duration: '7d',
                ),
              ],
              investigations: [buildVisitInvestigation(name: 'Complete Blood Count', note: 'Fasting')],
              attachments: [buildVisitAttachmentItem(label: 'Lab PDF')],
            ),
          ),
        ),
      );

      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(find.text('Complete Blood Count'), findsOneWidget);
      expect(find.text('Fasting'), findsOneWidget);
      expect(find.text('Lab PDF'), findsOneWidget);
      expect(find.text('1 prescription added'), findsOneWidget);
      expect(find.text('1 investigation to order'), findsOneWidget);
    });

    testWidgets('trivial: empty structured editors show empty-state copy', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier());

      expect(find.text('No prescriptions added yet.'), findsOneWidget);
      expect(find.text('No investigations added yet.'), findsOneWidget);
      expect(find.text('PDF, DOCX, JPG, PNG up to 25 MB each.'), findsOneWidget);
    });
  });

  group('VisitTreatmentSection — read-only vs editable', () {
    testWidgets('trivial: canEdit false disables treatment notes editor', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier(), canEdit: false);

      final notesSemantics = tester.getSemantics(find.bySemanticsIdentifier('treatment-notes-input'));
<<<<<<< HEAD
      expect(notesSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
=======
      expect(notesSemantics.flagsCollection.isEnabled, Tristate.isFalse);
>>>>>>> master
    });

    testWidgets('trivial: canEdit false hides structured editor mutation affordances', (tester) async {
      await _pumpTreatmentSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            visit: sampleEncounterVisit(
              treatmentPlans: [buildVisitTreatmentPlanItem()],
              investigations: [buildVisitInvestigation()],
              attachments: [buildVisitAttachmentItem()],
            ),
          ),
        ),
        canEdit: false,
      );

      expect(find.text('Add prescription'), findsNothing);
      expect(find.text('Add investigation'), findsNothing);
      expect(find.bySemanticsLabel('Remove Amoxicillin'), findsNothing);
      expect(find.bySemanticsLabel('Remove Complete Blood Count'), findsNothing);
      expect(find.bySemanticsLabel('Remove Lab PDF'), findsNothing);

<<<<<<< HEAD
      final dropzoneSemantics = tester.getSemantics(find.bySemanticsIdentifier('visit-attachments'));
      expect(dropzoneSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
=======
      final dropzone = find.bySemanticsIdentifier('visit-attachments');
      await tester.scrollUntilVisible(dropzone, 100);
      await pumpVisitsFrames(tester);
      final dropzoneSemantics = tester.getSemantics(dropzone);
      expect(dropzoneSemantics.flagsCollection.isEnabled, Tristate.isFalse);
>>>>>>> master
    });

    testWidgets('advanced: canEdit true shows add affordances in empty editors', (tester) async {
      await _pumpTreatmentSection(tester, docNotifier: _docNotifier(), canEdit: true);

      expect(find.text('Add prescription'), findsOneWidget);
      expect(find.text('Add investigation'), findsOneWidget);
    });
  });

  group('VisitTreatmentSection — rich-text notifier wiring', () {
    testWidgets('advanced: treatment notes change routes to updatePlan', (tester) async {
      final notifier = _docNotifier();
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      _driveRichText(tester, 'treatment-notes-input', 'Return if fever persists');
      await pumpVisitsFrames(tester);

      expect(notifier.updatePlanCallCount, greaterThan(0));
      expect(notifier.lastUpdatePlan, 'Return if fever persists');
    });

    testWidgets('invalid state: read-only mode does not route treatment notes to notifier', (tester) async {
      final notifier = _docNotifier();
      await _pumpTreatmentSection(tester, docNotifier: notifier, canEdit: false);

      _driveRichText(tester, 'treatment-notes-input', 'Should not save');
      await pumpVisitsFrames(tester);

      expect(notifier.updatePlanCallCount, 0);
    });
  });

  group('VisitTreatmentSection — treatment plan notifier wiring', () {
    testWidgets('advanced: create prescription routes to stageCreateTreatmentPlan with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      await tester.tap(find.text('Add prescription'));
      await pumpVisitsFrames(tester);
      await _submitTreatmentPlanDialog(
        tester,
        medicationQuery: 'Amox',
        dosage: '500 mg',
        frequencyLabel: 'Twice daily',
        durationLabel: '7 days',
      );

      expect(notifier.stageCreateTreatmentPlanCallCount, 1);
      expect(notifier.lastStageCreateTreatmentPlanMedicationName, 'Amoxicillin');
      expect(notifier.lastStageCreateTreatmentPlanMedicationId, 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm');
      expect(notifier.lastStageCreateTreatmentPlanDosage, '500 mg');
      expect(notifier.lastStageCreateTreatmentPlanFrequency, 'bd');
      expect(notifier.lastStageCreateTreatmentPlanDuration, '7d');
    });

    testWidgets('advanced: archive prescription routes to stageArchiveTreatmentPlan', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          visit: sampleEncounterVisit(treatmentPlans: [buildVisitTreatmentPlanItem()]),
        ),
      );
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      await tester.tap(find.bySemanticsLabel('Remove Amoxicillin'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageArchiveTreatmentPlanCallCount, 1);
      expect(notifier.lastStageArchiveTreatmentPlanId, encounterTestTreatmentPlanId);
    });

    testWidgets('advanced: edit prescription routes to stageUpdateTreatmentPlan with args', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          visit: sampleEncounterVisit(
            treatmentPlans: [
              buildVisitTreatmentPlanItem(
                dosage: '250 mg',
                frequency: 'od',
                duration: '3d',
              ),
            ],
          ),
        ),
      );
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      await tester.tap(find.bySemanticsLabel('Edit Amoxicillin'));
      await pumpVisitsFrames(tester);
      await _submitTreatmentPlanDialog(
        tester,
        medicationQuery: 'Amox',
        dosage: '500 mg',
        frequencyLabel: 'Twice daily',
        durationLabel: '7 days',
        submitLabel: 'Save changes',
      );

      expect(notifier.stageUpdateTreatmentPlanCallCount, 1);
      expect(notifier.lastStageUpdateTreatmentPlanId, encounterTestTreatmentPlanId);
      expect(notifier.lastStageUpdateTreatmentPlanDosage, '500 mg');
      expect(notifier.lastStageUpdateTreatmentPlanFrequency, 'bd');
      expect(notifier.lastStageUpdateTreatmentPlanDuration, '7d');
    });
  });

  group('VisitTreatmentSection — investigations notifier wiring', () {
    testWidgets('advanced: create investigation routes to stageCreateInvestigation with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      await tester.tap(find.text('Add investigation'));
      await pumpVisitsFrames(tester);
      await _submitInvestigationDialog(tester, investigationQuery: 'CBC', note: 'Fasting sample');

      expect(notifier.stageCreateInvestigationCallCount, 1);
      expect(notifier.lastStageCreateInvestigationName, 'Complete Blood Count');
      expect(notifier.lastStageCreateInvestigationNote, 'Fasting sample');
      expect(notifier.lastStageCreateInvestigationCatalogId, 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii');
    });

    testWidgets('advanced: archive investigation routes to stageArchiveInvestigation', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          visit: sampleEncounterVisit(investigations: [buildVisitInvestigation()]),
        ),
      );
      await _pumpTreatmentSection(tester, docNotifier: notifier);

      await tester.tap(find.bySemanticsLabel('Remove Complete Blood Count'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageArchiveInvestigationCallCount, 1);
      expect(notifier.lastStageArchiveInvestigationLineId, encounterTestInvestigationLineId);
    });

    testWidgets('advanced: edit investigation routes to stageUpdateInvestigation with args', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          visit: sampleEncounterVisit(
            investigations: [buildVisitInvestigation(note: 'Routine panel')],
          ),
        ),
      );
      await _pumpTreatmentSection(tester, docNotifier: notifier);

<<<<<<< HEAD
      await tester.tap(find.bySemanticsLabel('Edit Complete Blood Count'));
=======
      final editButton = find.bySemanticsLabel('Edit Complete Blood Count');
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
>>>>>>> master
      await pumpVisitsFrames(tester);
      await _submitInvestigationDialog(
        tester,
        investigationQuery: 'CBC',
        note: 'Fasting required',
        submitLabel: 'Save changes',
      );

      expect(notifier.stageUpdateInvestigationCallCount, 1);
      expect(notifier.lastStageUpdateInvestigationLineId, encounterTestInvestigationLineId);
      expect(notifier.lastStageUpdateInvestigationName, 'Complete Blood Count');
      expect(notifier.lastStageUpdateInvestigationNote, 'Fasting required');
      expect(notifier.lastStageUpdateInvestigationCatalogId, 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii');
      expect(notifier.lastStageUpdateInvestigationIdFlag, isTrue);
    });
  });

  group('VisitTreatmentSection — attachments notifier wiring', () {
    testWidgets('advanced: delete attachment routes to stageDeleteAttachment', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          visit: sampleEncounterVisit(attachments: [buildVisitAttachmentItem(label: 'Lab PDF')]),
        ),
      );
      await _pumpTreatmentSection(tester, docNotifier: notifier);

<<<<<<< HEAD
      await tester.tap(find.bySemanticsLabel('Remove Lab PDF'));
=======
      final removeButton = find.bySemanticsLabel('Remove Lab PDF');
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
>>>>>>> master
      await pumpVisitsFrames(tester);

      expect(notifier.stageDeleteAttachmentCallCount, 1);
      expect(notifier.lastStageDeleteAttachmentId, encounterTestAttachmentId);
    });
  });

  group('VisitTreatmentSection — saveStatus and errorMessage (not rendered here)', () {
    testWidgets('regression: saveStatus and errorMessage in state do not surface in this section', (tester) async {
      await _pumpTreatmentSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            saveStatus: DocumentationSaveStatus.stale,
            errorMessage: 'Documentation was updated elsewhere',
          ),
        ),
      );

      expect(find.textContaining('Documentation was updated'), findsNothing);
      expect(find.textContaining('Stale'), findsNothing);
    });
  });
}
