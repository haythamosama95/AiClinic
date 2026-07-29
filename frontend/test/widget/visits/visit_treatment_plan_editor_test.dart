import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_treatment_plan_editor.dart';

import '../../support/visit_encounter_test_support.dart';
import 'visit_widget_test_harness.dart';

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<TreatmentPlanItem> entries,
  bool canEdit = true,
  void Function({
    required String medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  })?
  onCreate,
  void Function(
    String id, {
    String? medicationName,
    String? medicationId,
    String? dosage,
    String? frequency,
    String? duration,
    String? notes,
  })?
  onUpdate,
  void Function(String id)? onArchive,
}) async {
  await pumpVisitsSurface(
    tester,
    child: VisitTreatmentPlanEditor(
      entries: entries,
      canEdit: canEdit,
      onCreate: onCreate ??
          ({
            required medicationName,
            medicationId,
            dosage,
            frequency,
            duration,
            notes,
          }) {},
      onUpdate: onUpdate ??
          (id, {medicationName, medicationId, dosage, frequency, duration, notes}) {},
      onArchive: onArchive ?? (_) {},
    ),
  );
  await pumpVisitsFrames(tester);
}

Future<void> _tapSemantics(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpVisitsFrames(tester);
}

void main() {
  group('VisitTreatmentPlanEditor', () {
    group('trivial:', () {
      testWidgets('empty list shows empty-state copy and Add control', (tester) async {
        await _pumpEditor(tester, entries: const []);

        expect(find.text('Prescriptions'), findsOneWidget);
        expect(find.text('Add medications with dosage, frequency, and duration.'), findsOneWidget);
        expect(find.text('No prescriptions added yet.'), findsOneWidget);
        expect(find.text('Add prescription'), findsOneWidget);
        expect(find.byType(TreatmentPlanEntryCard), findsNothing);
      });

      testWidgets('several entries render one card each with medication and dosing fields', (tester) async {
        final entries = [
          buildVisitTreatmentPlanItem(
            id: 'tp-1',
            medicationName: 'Amoxicillin',
            dosage: '500 mg',
            frequency: 'bd',
            duration: '7d',
          ),
          buildVisitTreatmentPlanItem(
            id: 'tp-2',
            medicationName: 'Ibuprofen',
            dosage: '200 mg',
            frequency: 'prn',
            duration: '3d',
          ),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.text('2 prescriptions added'), findsOneWidget);
        expect(find.byType(TreatmentPlanEntryCard), findsNWidgets(2));
        expect(find.text('Amoxicillin'), findsOneWidget);
        expect(find.text('500 mg'), findsOneWidget);
        expect(find.text('Twice daily'), findsOneWidget);
        expect(find.text('7 days'), findsOneWidget);
        expect(find.text('Ibuprofen'), findsOneWidget);
        expect(find.text('As needed'), findsOneWidget);
        expect(find.text('Add another prescription'), findsOneWidget);
      });

      testWidgets('tapping Add opens TreatmentPlanFormDialog', (tester) async {
        await _pumpEditor(tester, entries: const []);

        await tester.tap(find.text('Add prescription'));
        await pumpVisitsFrames(tester);

        expect(find.byType(TreatmentPlanFormDialog), findsOneWidget);
      });

      testWidgets('remove on a row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final entry = buildVisitTreatmentPlanItem(id: 'tp-archive-me', medicationName: 'Amoxicillin');

        await _pumpEditor(
          tester,
          entries: [entry],
          onArchive: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Amoxicillin');

        expect(archivedId, 'tp-archive-me');
      });
    });

    group('advanced:', () {
      testWidgets('tapping edit on a row opens TreatmentPlanFormDialog', (tester) async {
        final entry = buildVisitTreatmentPlanItem(id: 'tp-edit-me', medicationName: 'Amoxicillin');

        await _pumpEditor(tester, entries: [entry]);

        await _tapSemantics(tester, 'Edit Amoxicillin');

        expect(find.byType(TreatmentPlanFormDialog), findsOneWidget);
      });

      testWidgets('read-only mode hides Add and per-row edit/remove affordances', (tester) async {
        final entry = buildVisitTreatmentPlanItem(medicationName: 'Amoxicillin');

        await _pumpEditor(tester, entries: [entry], canEdit: false);

        expect(find.text('Add another prescription'), findsNothing);
        expect(find.bySemanticsLabel('Edit Amoxicillin'), findsNothing);
        expect(find.bySemanticsLabel('Remove Amoxicillin'), findsNothing);
        expect(find.text('Amoxicillin'), findsOneWidget);
      });

      testWidgets('empty read-only state hides Add control', (tester) async {
        await _pumpEditor(tester, entries: const [], canEdit: false);

        expect(find.text('No prescriptions added yet.'), findsOneWidget);
        expect(find.text('Add prescription'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('single item uses singular count copy', (tester) async {
        await _pumpEditor(tester, entries: [buildVisitTreatmentPlanItem()]);

        expect(find.text('1 prescription added'), findsOneWidget);
        expect(find.byType(TreatmentPlanEntryCard), findsOneWidget);
      });

      testWidgets('many items render one card each', (tester) async {
        final entries = List.generate(
          20,
          (index) => buildVisitTreatmentPlanItem(
            id: 'tp-$index',
            medicationName: 'Medication $index',
          ),
        );

        await _pumpEditor(tester, entries: entries);

        expect(find.byType(TreatmentPlanEntryCard), findsNWidgets(20));
        expect(find.text('20 prescriptions added'), findsOneWidget);
      });

      testWidgets('null dosage and frequency render em dash placeholders', (tester) async {
        await _pumpEditor(
          tester,
          entries: [
            buildVisitTreatmentPlanItem(
              medicationName: 'Vitamin D',
              dosage: null,
              frequency: null,
              duration: null,
            ),
          ],
        );

        expect(find.text('Vitamin D'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(3));
      });

      testWidgets('very long text does not throw', (tester) async {
        final longName = 'Med ' * 100;

        await _pumpEditor(
          tester,
          entries: [
            buildVisitTreatmentPlanItem(medicationName: longName, dosage: 'dose'),
          ],
        );

        expect(find.byType(TreatmentPlanEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('duplicate ids still render distinct rows', (tester) async {
        const sharedId = 'duplicate-id';
        final entries = [
          buildVisitTreatmentPlanItem(id: sharedId, medicationName: 'Alpha'),
          buildVisitTreatmentPlanItem(id: sharedId, medicationName: 'Beta'),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.byType(TreatmentPlanEntryCard), findsNWidgets(2));
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
      });
    });
  });
}
