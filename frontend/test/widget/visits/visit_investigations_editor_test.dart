<<<<<<< HEAD
=======
import 'package:flutter/material.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_investigations_editor.dart';

<<<<<<< HEAD
import '../../support/visit_encounter_test_support.dart';
=======
>>>>>>> master
import 'visit_widget_test_harness.dart';

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<VisitInvestigation> entries,
  bool canEdit = true,
  void Function({required String name, String? note, String? investigationId})? onCreate,
  void Function(String id, {required String name, String? note, String? investigationId})? onUpdate,
  void Function(String id)? onArchive,
}) async {
  await pumpVisitsSurface(
    tester,
<<<<<<< HEAD
    child: VisitInvestigationsEditor(
      entries: entries,
      canEdit: canEdit,
      onCreate: onCreate ?? ({required name, note, investigationId}) {},
      onUpdate: onUpdate ?? (id, {required name, note, investigationId}) {},
      onArchive: onArchive ?? (_) {},
=======
    child: SingleChildScrollView(
      child: VisitInvestigationsEditor(
        entries: entries,
        canEdit: canEdit,
        onCreate: onCreate ?? ({required name, note, investigationId}) {},
        onUpdate: onUpdate ?? (id, {required name, note, investigationId}) {},
        onArchive: onArchive ?? (_) {},
      ),
>>>>>>> master
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
  group('VisitInvestigationsEditor', () {
    group('trivial:', () {
      testWidgets('empty list shows empty-state copy and Add control', (tester) async {
        await _pumpEditor(tester, entries: const []);

        expect(find.text('Ordered investigations'), findsOneWidget);
        expect(find.text('Add labs, imaging, or other diagnostic tests.'), findsOneWidget);
        expect(find.text('No investigations added yet.'), findsOneWidget);
        expect(find.text('Add investigation'), findsOneWidget);
        expect(find.byType(InvestigationEntryCard), findsNothing);
      });

      testWidgets('several entries render one card each with name and note', (tester) async {
        final entries = [
          buildVisitInvestigation(id: 'inv-1', name: 'Complete Blood Count', note: 'Fasting'),
          buildVisitInvestigation(id: 'inv-2', name: 'Chest X-Ray', note: 'PA view'),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.text('2 investigations to order'), findsOneWidget);
        expect(find.byType(InvestigationEntryCard), findsNWidgets(2));
        expect(find.text('Complete Blood Count'), findsOneWidget);
        expect(find.text('Fasting'), findsOneWidget);
        expect(find.text('Chest X-Ray'), findsOneWidget);
        expect(find.text('PA view'), findsOneWidget);
        expect(find.text('Add another investigation'), findsOneWidget);
      });

      testWidgets('tapping Add opens InvestigationFormDialog', (tester) async {
        await _pumpEditor(tester, entries: const []);

        await tester.tap(find.text('Add investigation'));
        await pumpVisitsFrames(tester);

        expect(find.byType(InvestigationFormDialog), findsOneWidget);
      });

      testWidgets('remove on a row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final entry = buildVisitInvestigation(id: 'inv-archive-me', name: 'Complete Blood Count');

        await _pumpEditor(
          tester,
          entries: [entry],
          onArchive: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Complete Blood Count');

        expect(archivedId, 'inv-archive-me');
      });
    });

    group('advanced:', () {
      testWidgets('tapping edit on a row opens InvestigationFormDialog', (tester) async {
        final entry = buildVisitInvestigation(id: 'inv-edit-me', name: 'Complete Blood Count');

        await _pumpEditor(tester, entries: [entry]);

        await _tapSemantics(tester, 'Edit Complete Blood Count');

        expect(find.byType(InvestigationFormDialog), findsOneWidget);
      });

      testWidgets('read-only mode hides Add and per-row edit/remove affordances', (tester) async {
        final entry = buildVisitInvestigation(name: 'Complete Blood Count');

        await _pumpEditor(tester, entries: [entry], canEdit: false);

        expect(find.text('Add another investigation'), findsNothing);
        expect(find.bySemanticsLabel('Edit Complete Blood Count'), findsNothing);
        expect(find.bySemanticsLabel('Remove Complete Blood Count'), findsNothing);
        expect(find.text('Complete Blood Count'), findsOneWidget);
      });

      testWidgets('empty read-only state hides Add control', (tester) async {
        await _pumpEditor(tester, entries: const [], canEdit: false);

        expect(find.text('No investigations added yet.'), findsOneWidget);
        expect(find.text('Add investigation'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('single item uses singular count copy', (tester) async {
        await _pumpEditor(tester, entries: [buildVisitInvestigation()]);

        expect(find.text('1 investigation to order'), findsOneWidget);
        expect(find.byType(InvestigationEntryCard), findsOneWidget);
      });

      testWidgets('many items render one card each', (tester) async {
        final entries = List.generate(
          20,
          (index) => buildVisitInvestigation(
            id: 'inv-$index',
            name: 'Investigation $index',
          ),
        );

        await _pumpEditor(tester, entries: entries);

<<<<<<< HEAD
=======
        expect(find.text('Investigation 0'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Investigation 19'), 100);
        await pumpVisitsFrames(tester);
>>>>>>> master
        expect(find.byType(InvestigationEntryCard), findsNWidgets(20));
        expect(find.text('20 investigations to order'), findsOneWidget);
      });

      testWidgets('null note renders em dash placeholder', (tester) async {
        await _pumpEditor(
          tester,
          entries: [
            buildVisitInvestigation(name: 'MRI', note: null),
          ],
        );

        expect(find.text('MRI'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
      });

      testWidgets('empty note renders em dash placeholder', (tester) async {
        await _pumpEditor(
          tester,
          entries: [
            buildVisitInvestigation(name: 'MRI', note: '   '),
          ],
        );

        expect(find.text('—'), findsOneWidget);
      });

      testWidgets('very long text does not throw', (tester) async {
        final longName = 'Test ' * 100;
        final longNote = 'Note ' * 100;

        await _pumpEditor(
          tester,
          entries: [
            buildVisitInvestigation(name: longName, note: longNote),
          ],
        );

        expect(find.byType(InvestigationEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('duplicate ids still render distinct rows', (tester) async {
        const sharedId = 'duplicate-id';
        final entries = [
          buildVisitInvestigation(id: sharedId, name: 'Alpha'),
          buildVisitInvestigation(id: sharedId, name: 'Beta'),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.byType(InvestigationEntryCard), findsNWidgets(2));
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
      });
    });
  });
}
