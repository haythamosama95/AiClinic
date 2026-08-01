import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

<<<<<<< HEAD
=======
import 'package:ai_clinic/core/ui/components/app_button.dart';
>>>>>>> master
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_medical_background_editor.dart';

<<<<<<< HEAD
import '../../support/visit_encounter_test_support.dart';
=======
>>>>>>> master
import 'visit_widget_test_harness.dart';

Future<void> _pumpEditor(
  WidgetTester tester, {
  List<PatientChronicCondition> chronicConditions = const [],
  List<PatientAllergy> allergies = const [],
  List<PatientMedication> currentMedications = const [],
  bool canEdit = true,
  void Function(String title, String? note)? onCreateCondition,
  void Function(String id, String title, String? note)? onUpdateCondition,
  void Function(String id)? onArchiveCondition,
  void Function(String title, String? note)? onCreateAllergy,
  void Function(String id, String title, String? note)? onUpdateAllergy,
  void Function(String id)? onArchiveAllergy,
  void Function(String title, String? note)? onCreateMedication,
  void Function(String id, String title, String? note)? onUpdateMedication,
  void Function(String id)? onArchiveMedication,
}) async {
  await pumpVisitsSurface(
    tester,
    child: VisitMedicalBackgroundEditor(
      chronicConditions: chronicConditions,
      allergies: allergies,
      currentMedications: currentMedications,
      canEdit: canEdit,
<<<<<<< HEAD
      onCreateCondition: onCreateCondition ?? (_, __) {},
      onUpdateCondition: onUpdateCondition ?? (_, __, ___) {},
      onArchiveCondition: onArchiveCondition ?? (_) {},
      onCreateAllergy: onCreateAllergy ?? (_, __) {},
      onUpdateAllergy: onUpdateAllergy ?? (_, __, ___) {},
      onArchiveAllergy: onArchiveAllergy ?? (_) {},
      onCreateMedication: onCreateMedication ?? (_, __) {},
      onUpdateMedication: onUpdateMedication ?? (_, __, ___) {},
=======
      onCreateCondition: onCreateCondition ?? (_, _) {},
      onUpdateCondition: onUpdateCondition ?? (_, _, _) {},
      onArchiveCondition: onArchiveCondition ?? (_) {},
      onCreateAllergy: onCreateAllergy ?? (_, _) {},
      onUpdateAllergy: onUpdateAllergy ?? (_, _, _) {},
      onArchiveAllergy: onArchiveAllergy ?? (_) {},
      onCreateMedication: onCreateMedication ?? (_, _) {},
      onUpdateMedication: onUpdateMedication ?? (_, _, _) {},
>>>>>>> master
      onArchiveMedication: onArchiveMedication ?? (_) {},
    ),
  );
  await pumpVisitsFrames(tester);
}

<<<<<<< HEAD
Finder _columnForLabel(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
}

Future<void> _tapAddInColumn(WidgetTester tester, String columnLabel) async {
  final column = _columnForLabel(columnLabel);
  final addButton = find.descendant(of: column, matching: find.text('Add'));
=======
Finder _categoryColumnScope(String columnLabel) {
  return find.ancestor(
    of: find.text(columnLabel),
    matching: find.byType(Column),
  ).first;
}

Future<void> _tapAddInColumn(WidgetTester tester, String columnLabel) async {
  final addButton = find.descendant(
    of: _categoryColumnScope(columnLabel),
    matching: find.widgetWithText(AppButton, 'Add'),
  );
>>>>>>> master
  await tester.ensureVisible(addButton);
  await tester.tap(addButton);
  await pumpVisitsFrames(tester);
}

Future<void> _tapSemantics(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitMedicalBackgroundEditor', () {
    group('trivial:', () {
      testWidgets('empty editor shows section copy and three column empty states', (tester) async {
        await _pumpEditor(tester);

        expect(find.text('Medical background'), findsOneWidget);
        expect(
          find.text('Chronic conditions, allergies, and current medications relevant to this visit.'),
          findsOneWidget,
        );
        expect(find.text('Chronic conditions'), findsOneWidget);
        expect(find.text('Allergies'), findsOneWidget);
        expect(find.text('Current medications'), findsOneWidget);
        expect(find.text('Nothing documented yet'), findsNWidgets(3));
        expect(find.text('Add'), findsNWidgets(3));
        expect(find.byType(MedicalBackgroundEntryCard), findsNothing);
      });

      testWidgets('each column Add opens MedicalBackgroundFormDialog', (tester) async {
        await _pumpEditor(tester);

        await _tapAddInColumn(tester, 'Chronic conditions');
        expect(find.byType(MedicalBackgroundFormDialog), findsOneWidget);

        await tester.tap(find.text('Cancel').first);
        await pumpVisitsFrames(tester);

        await _tapAddInColumn(tester, 'Allergies');
        expect(find.byType(MedicalBackgroundFormDialog), findsOneWidget);

        await tester.tap(find.text('Cancel').first);
        await pumpVisitsFrames(tester);

        await _tapAddInColumn(tester, 'Current medications');
        expect(find.byType(MedicalBackgroundFormDialog), findsOneWidget);
      });

      testWidgets('populated columns render entry cards with title and note', (tester) async {
        await _pumpEditor(
          tester,
          chronicConditions: [
            buildPatientChronicCondition(name: 'Type 2 diabetes', note: 'Well controlled'),
          ],
          allergies: [
            buildPatientAllergy(substance: 'Penicillin', reaction: 'Severe'),
          ],
          currentMedications: [
            buildPatientMedication(name: 'Metformin', note: '500 mg twice daily'),
          ],
        );

        expect(find.byType(MedicalBackgroundEntryCard), findsNWidgets(3));
        expect(find.text('Type 2 diabetes'), findsOneWidget);
        expect(find.text('Well controlled'), findsOneWidget);
        expect(find.text('Penicillin'), findsOneWidget);
        expect(find.text('Severe'), findsOneWidget);
        expect(find.text('Metformin'), findsOneWidget);
        expect(find.text('500 mg twice daily'), findsOneWidget);
        expect(find.text('Add'), findsNWidgets(3));
      });
    });

    group('advanced:', () {
      testWidgets('remove on condition row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final condition = buildPatientChronicCondition(id: 'cond-archive-me', name: 'Asthma');

        await _pumpEditor(
          tester,
          chronicConditions: [condition],
          onArchiveCondition: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Asthma');

        expect(archivedId, 'cond-archive-me');
      });

      testWidgets('remove on allergy row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final allergy = buildPatientAllergy(id: 'allergy-archive-me', substance: 'Peanuts');

        await _pumpEditor(
          tester,
          allergies: [allergy],
          onArchiveAllergy: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Peanuts');

        expect(archivedId, 'allergy-archive-me');
      });

      testWidgets('remove on medication row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final medication = buildPatientMedication(id: 'med-archive-me', name: 'Lisinopril');

        await _pumpEditor(
          tester,
          currentMedications: [medication],
          onArchiveMedication: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Lisinopril');

        expect(archivedId, 'med-archive-me');
      });

      testWidgets('edit on condition row opens MedicalBackgroundFormDialog', (tester) async {
        final condition = buildPatientChronicCondition(name: 'Asthma');

        await _pumpEditor(tester, chronicConditions: [condition]);

        await _tapSemantics(tester, 'Edit Asthma');

        expect(find.byType(MedicalBackgroundFormDialog), findsOneWidget);
      });

      testWidgets('read-only mode hides Add and per-row edit/remove affordances', (tester) async {
        await _pumpEditor(
          tester,
          canEdit: false,
          chronicConditions: [buildPatientChronicCondition(name: 'Asthma')],
          allergies: [buildPatientAllergy(substance: 'Peanuts')],
          currentMedications: [buildPatientMedication(name: 'Lisinopril')],
        );

        expect(find.text('Add'), findsNothing);
        expect(find.bySemanticsLabel('Edit Asthma'), findsNothing);
        expect(find.bySemanticsLabel('Remove Asthma'), findsNothing);
        expect(find.bySemanticsLabel('Edit Peanuts'), findsNothing);
        expect(find.bySemanticsLabel('Remove Lisinopril'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('allergy reaction note displays AllergySeverityOptions value verbatim', (tester) async {
        await _pumpEditor(
          tester,
          allergies: [
            buildPatientAllergy(
              substance: 'Penicillin',
              reaction: AllergySeverityOptions.items['Life-threatening'],
            ),
          ],
        );

        expect(find.text('Life-threatening'), findsOneWidget);
      });

      testWidgets('null notes render em dash placeholder in each column', (tester) async {
        await _pumpEditor(
          tester,
          chronicConditions: [buildPatientChronicCondition(name: 'Asthma', note: null)],
          allergies: [buildPatientAllergy(substance: 'Peanuts', reaction: null)],
          currentMedications: [buildPatientMedication(name: 'Lisinopril', note: null)],
        );

        expect(find.text('—'), findsNWidgets(3));
      });

      testWidgets('many entries per column render one card each', (tester) async {
        final conditions = List.generate(
          10,
          (index) => buildPatientChronicCondition(
            id: 'cond-$index',
            name: 'Condition $index',
          ),
        );

        await _pumpEditor(tester, chronicConditions: conditions);

        expect(find.byType(MedicalBackgroundEntryCard), findsNWidgets(10));
      });

      testWidgets('very long text does not throw', (tester) async {
        final longTitle = 'Title ' * 100;
        final longNote = 'Note ' * 100;

        await _pumpEditor(
          tester,
          chronicConditions: [
            buildPatientChronicCondition(name: longTitle, note: longNote),
          ],
        );

        expect(find.byType(MedicalBackgroundEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
