import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_findings_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_vital_signs_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_form_dialog.dart';

import 'visit_widget_test_harness.dart';

const _bpCatalogId = 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv';

final _bloodPressureCatalog = [
  const CatalogItem(id: _bpCatalogId, name: 'Blood Pressure', defaultUnit: 'mmHg'),
];

Future<StubVisitDocumentationNotifier> _pumpFindingsSection(
  WidgetTester tester, {
  required StubVisitDocumentationNotifier docNotifier,
  bool canEdit = true,
}) async {
  await pumpVisitsSurface(
    tester,
    child: SingleChildScrollView(
      child: VisitFindingsSection(visitId: encounterTestVisitId, canEdit: canEdit),
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
    state ?? sampleEncounterDocState(predefinedVitalSigns: _bloodPressureCatalog),
  );
}

void _driveRichText(WidgetTester tester, String semanticsId, String text) {
  final finder = find.descendant(
    of: find.bySemanticsIdentifier(semanticsId),
    matching: find.byType(AppRichTextEditor),
  );
  expect(finder, findsOneWidget);
  final editor = tester.widget<AppRichTextEditor>(finder);
  expect(editor.controller, isNotNull);
  setQuillControllerPlainText(editor.controller!, text);
}

Future<void> _submitVitalSignDialog(WidgetTester tester, {required String value}) async {
  final dialog = find.byType(VitalSignFormDialog);
  expect(dialog, findsOneWidget);
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(EditableText)),
    value,
  );
  await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitFindingsSection — build & structure', () {
    testWidgets('trivial: builds with administrator session and in-progress visit', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier());

      expect(find.byType(VisitFindingsSection), findsOneWidget);
      expect(find.text('Findings & diagnosis'), findsOneWidget);
    });

    testWidgets('trivial: shows section heading, subtitle, and field labels', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier());

      expect(find.text('Document physical examination, vital signs, and clinical assessment.'), findsOneWidget);
      expect(find.text('Physical examination'), findsOneWidget);
      expect(find.text('Vital signs'), findsOneWidget);
      expect(find.text('Diagnosis'), findsOneWidget);
      expect(
        find.text('Add each measurement via the dialog; recorded values appear as cards below.'),
        findsOneWidget,
      );
    });

    testWidgets('trivial: contains rich-text editors and vital signs editor', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier());

      expect(find.bySemanticsIdentifier('physical-examination-input'), findsOneWidget);
      expect(find.bySemanticsIdentifier('diagnosis-input'), findsOneWidget);
      expect(find.byType(VisitVitalSignsEditor), findsOneWidget);
      expect(find.text('Recorded measurements'), findsOneWidget);
    });
  });

  group('VisitFindingsSection — pre-populated & empty state', () {
    testWidgets('trivial: renders existing examination and diagnosis text', (tester) async {
      await _pumpFindingsSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            predefinedVitalSigns: _bloodPressureCatalog,
            examination: 'Lungs clear bilaterally',
            diagnosis: 'Acute pharyngitis',
          ),
        ),
      );

      expect(find.textContaining('Lungs clear bilaterally'), findsOneWidget);
      expect(find.textContaining('Acute pharyngitis'), findsOneWidget);
    });

    testWidgets('trivial: renders existing vital sign cards', (tester) async {
      await _pumpFindingsSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            predefinedVitalSigns: _bloodPressureCatalog,
            visit: sampleEncounterVisit(vitalSigns: [buildVisitVitalSign(value: '118/76')]),
          ),
        ),
      );

      expect(find.text('BLOOD PRESSURE'), findsOneWidget);
      expect(find.text('118/76'), findsOneWidget);
      expect(find.text('1 vital sign documented'), findsOneWidget);
    });

    testWidgets('trivial: empty vital signs shows empty-state copy', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier());

      expect(find.text('No vital signs recorded yet.'), findsOneWidget);
      expect(find.text('Add each measurement as it is taken.'), findsOneWidget);
      expect(find.text('Add vital sign'), findsOneWidget);
    });

    testWidgets('edge case: empty vital-sign catalog hides add affordance', (tester) async {
      await _pumpFindingsSection(
        tester,
        docNotifier: _docNotifier(state: sampleEncounterDocState(predefinedVitalSigns: const [])),
      );

      expect(find.text('No vital signs recorded yet.'), findsOneWidget);
      expect(find.text('Add vital sign'), findsNothing);
    });
  });

  group('VisitFindingsSection — read-only vs editable', () {
    testWidgets('trivial: canEdit false disables rich-text editors', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier(), canEdit: false);

      final examSemantics = tester.getSemantics(find.bySemanticsIdentifier('physical-examination-input'));
      expect(examSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);

      final diagnosisSemantics = tester.getSemantics(find.bySemanticsIdentifier('diagnosis-input'));
      expect(diagnosisSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
    });

    testWidgets('trivial: canEdit false hides vital sign add and remove affordances', (tester) async {
      await _pumpFindingsSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            predefinedVitalSigns: _bloodPressureCatalog,
            visit: sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]),
          ),
        ),
        canEdit: false,
      );

      expect(find.text('Add vital sign'), findsNothing);
      expect(find.text('Add another vital sign'), findsNothing);
      expect(find.bySemanticsLabel('Remove Blood Pressure'), findsNothing);
      expect(find.bySemanticsLabel('Edit Blood Pressure'), findsNothing);
    });

    testWidgets('advanced: canEdit true shows add vital sign affordance when catalog available', (tester) async {
      await _pumpFindingsSection(tester, docNotifier: _docNotifier(), canEdit: true);

      expect(find.text('Add vital sign'), findsOneWidget);
    });
  });

  group('VisitFindingsSection — rich-text notifier wiring', () {
    testWidgets('advanced: physical examination change routes to updateExamination', (tester) async {
      final notifier = _docNotifier();
      await _pumpFindingsSection(tester, docNotifier: notifier);

      _driveRichText(tester, 'physical-examination-input', 'Abdomen soft, non-tender');
      await pumpVisitsFrames(tester);

      expect(notifier.updateExaminationCallCount, greaterThan(0));
      expect(notifier.lastUpdateExamination, 'Abdomen soft, non-tender');
    });

    testWidgets('advanced: diagnosis change routes to updateDiagnosis', (tester) async {
      final notifier = _docNotifier();
      await _pumpFindingsSection(tester, docNotifier: notifier);

      _driveRichText(tester, 'diagnosis-input', 'Viral URI');
      await pumpVisitsFrames(tester);

      expect(notifier.updateDiagnosisCallCount, greaterThan(0));
      expect(notifier.lastUpdateDiagnosis, 'Viral URI');
    });

    testWidgets('invalid state: read-only mode does not route rich-text changes to notifier', (tester) async {
      final notifier = _docNotifier();
      await _pumpFindingsSection(tester, docNotifier: notifier, canEdit: false);

      _driveRichText(tester, 'physical-examination-input', 'Should not save');
      _driveRichText(tester, 'diagnosis-input', 'Should not save');
      await pumpVisitsFrames(tester);

      expect(notifier.updateExaminationCallCount, 0);
      expect(notifier.updateDiagnosisCallCount, 0);
    });
  });

  group('VisitFindingsSection — vital signs notifier wiring', () {
    testWidgets('advanced: create vital sign routes to stageCreateVitalSign with args', (tester) async {
      final notifier = _docNotifier();
      await _pumpFindingsSection(tester, docNotifier: notifier);

      await tester.tap(find.text('Add vital sign'));
      await pumpVisitsFrames(tester);
      await _submitVitalSignDialog(tester, value: '118/76');

      expect(notifier.stageCreateVitalSignCallCount, 1);
      expect(notifier.lastStageCreateVitalSignName, 'Blood Pressure');
      expect(notifier.lastStageCreateVitalSignValue, '118/76');
      expect(notifier.lastStageCreateVitalSignUnit, 'mmHg');
      expect(notifier.lastStageCreateVitalSignPredefinedId, _bpCatalogId);
    });

    testWidgets('advanced: archive vital sign routes to stageArchiveVitalSign', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          predefinedVitalSigns: _bloodPressureCatalog,
          visit: sampleEncounterVisit(vitalSigns: [buildVisitVitalSign()]),
        ),
      );
      await _pumpFindingsSection(tester, docNotifier: notifier);

      await tester.tap(find.bySemanticsLabel('Remove Blood Pressure'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageArchiveVitalSignCallCount, 1);
      expect(notifier.lastStageArchiveVitalSignId, encounterTestVitalSignId);
    });

    testWidgets('advanced: edit vital sign routes to stageUpdateVitalSign with args', (tester) async {
      final notifier = _docNotifier(
        state: sampleEncounterDocState(
          predefinedVitalSigns: _bloodPressureCatalog,
          visit: sampleEncounterVisit(vitalSigns: [buildVisitVitalSign(value: '120/80')]),
        ),
      );
      await _pumpFindingsSection(tester, docNotifier: notifier);

      await tester.tap(find.bySemanticsLabel('Edit Blood Pressure'));
      await pumpVisitsFrames(tester);

      final dialog = find.byType(VitalSignFormDialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(EditableText)),
        '122/82',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await pumpVisitsFrames(tester);

      expect(notifier.stageUpdateVitalSignCallCount, 1);
      expect(notifier.lastStageUpdateVitalSignId, encounterTestVitalSignId);
      expect(notifier.lastStageUpdateVitalSignValue, '122/82');
      expect(notifier.lastStageUpdateVitalSignName, 'Blood Pressure');
    });
  });

  group('VisitFindingsSection — saveStatus and errorMessage (not rendered here)', () {
    testWidgets('regression: saveStatus and errorMessage in state do not surface in this section', (tester) async {
      await _pumpFindingsSection(
        tester,
        docNotifier: _docNotifier(
          state: sampleEncounterDocState(
            predefinedVitalSigns: _bloodPressureCatalog,
            saveStatus: DocumentationSaveStatus.saving,
            errorMessage: 'Stale documentation conflict',
          ),
        ),
      );

      expect(find.textContaining('Stale documentation'), findsNothing);
      expect(find.textContaining('Saving'), findsNothing);
    });
  });
}
