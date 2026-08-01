<<<<<<< HEAD
import 'package:flutter/material.dart';
=======
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_vital_signs_editor.dart';

<<<<<<< HEAD
import '../../support/visit_encounter_test_support.dart';
=======
>>>>>>> master
import 'visit_widget_test_harness.dart';

const _catalog = <CatalogItem>[
  CatalogItem(id: 'vs-bp', name: 'Blood Pressure', defaultUnit: 'mmHg'),
  CatalogItem(id: 'vs-hr', name: 'Heart Rate', defaultUnit: 'bpm'),
  CatalogItem(id: 'vs-temp', name: 'Temperature', defaultUnit: '°C'),
];

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<VisitVitalSign> entries,
  List<CatalogItem> catalog = _catalog,
  bool canEdit = true,
  void Function({required String name, required String value, String? unit, String? predefinedVitalSignId})? onCreate,
  void Function(String id, {required String name, required String value, String? unit, String? predefinedVitalSignId})?
  onUpdate,
  void Function(String id)? onArchive,
}) async {
  await pumpVisitsSurface(
    tester,
    child: VisitVitalSignsEditor(
      entries: entries,
      catalog: catalog,
      canEdit: canEdit,
<<<<<<< HEAD
      onCreate: onCreate ?? (_) {},
      onUpdate: onUpdate ?? (_, {required name, required value, unit, predefinedVitalSignId}) {},
=======
      onCreate: onCreate ??
          ({required name, required value, unit, predefinedVitalSignId}) {},
      onUpdate: onUpdate ??
          (id, {required name, required value, unit, predefinedVitalSignId}) {},
>>>>>>> master
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
  group('VisitVitalSignsEditor', () {
    group('trivial:', () {
      testWidgets('empty list shows empty-state copy and Add control when catalog allows', (tester) async {
        await _pumpEditor(tester, entries: const []);

        expect(find.text('Recorded measurements'), findsOneWidget);
        expect(find.text('Add each measurement as it is taken.'), findsOneWidget);
        expect(find.text('No vital signs recorded yet.'), findsOneWidget);
        expect(find.text('Add vital sign'), findsOneWidget);
        expect(find.byType(VitalSignEntryCard), findsNothing);
      });

      testWidgets('several entries render one card each with name, value, and unit', (tester) async {
        final entries = [
          buildVisitVitalSign(id: 'vs-1', name: 'Blood Pressure', value: '120/80', unit: 'mmHg'),
          buildVisitVitalSign(id: 'vs-2', name: 'Heart Rate', value: '72', unit: 'bpm'),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.text('2 vital signs documented'), findsOneWidget);
        expect(find.byType(VitalSignEntryCard), findsNWidgets(2));
        expect(find.text('BLOOD PRESSURE'), findsOneWidget);
<<<<<<< HEAD
        expect(find.text('120/80'), findsOneWidget);
        expect(find.text('HEART RATE'), findsOneWidget);
        expect(find.text('72'), findsOneWidget);
        expect(find.textContaining('mmHg'), findsOneWidget);
        expect(find.textContaining('bpm'), findsOneWidget);
=======
        expect(find.text('HEART RATE'), findsOneWidget);
        final cards = tester.widgetList<VitalSignEntryCard>(find.byType(VitalSignEntryCard)).toList();
        expect(cards.map((card) => card.value), containsAll(['120/80', '72']));
        expect(cards.map((card) => card.unit), containsAll(['mmHg', 'bpm']));
>>>>>>> master
        expect(find.text('Add another vital sign'), findsOneWidget);
      });

      testWidgets('tapping Add opens VitalSignFormDialog', (tester) async {
        await _pumpEditor(tester, entries: const []);

        await tester.tap(find.text('Add vital sign'));
        await pumpVisitsFrames(tester);

        expect(find.byType(VitalSignFormDialog), findsOneWidget);
      });

      testWidgets('remove on a row invokes archive callback with correct id', (tester) async {
        String? archivedId;
        final entry = buildVisitVitalSign(id: 'vs-archive-me', name: 'Blood Pressure');

        await _pumpEditor(
          tester,
          entries: [entry],
          onArchive: (id) => archivedId = id,
        );

        await _tapSemantics(tester, 'Remove Blood Pressure');

        expect(archivedId, 'vs-archive-me');
      });
    });

    group('advanced:', () {
      testWidgets('tapping edit on a row opens VitalSignFormDialog', (tester) async {
        final entry = buildVisitVitalSign(id: 'vs-edit-me', name: 'Blood Pressure');

        await _pumpEditor(tester, entries: [entry]);

        await _tapSemantics(tester, 'Edit Blood Pressure');

        expect(find.byType(VitalSignFormDialog), findsOneWidget);
      });

      testWidgets('read-only mode hides Add and per-row edit/remove affordances', (tester) async {
        final entry = buildVisitVitalSign(name: 'Blood Pressure');

        await _pumpEditor(tester, entries: [entry], canEdit: false);

        expect(find.text('Add another vital sign'), findsNothing);
        expect(find.bySemanticsLabel('Edit Blood Pressure'), findsNothing);
        expect(find.bySemanticsLabel('Remove Blood Pressure'), findsNothing);
        expect(find.text('BLOOD PRESSURE'), findsOneWidget);
      });

      testWidgets('empty read-only state hides Add control', (tester) async {
        await _pumpEditor(tester, entries: const [], canEdit: false);

        expect(find.text('No vital signs recorded yet.'), findsOneWidget);
        expect(find.text('Add vital sign'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('single item uses singular count copy', (tester) async {
        await _pumpEditor(tester, entries: [buildVisitVitalSign()]);

        expect(find.text('1 vital sign documented'), findsOneWidget);
        expect(find.byType(VitalSignEntryCard), findsOneWidget);
      });

      testWidgets('many items render one card each', (tester) async {
        final entries = List.generate(
          20,
          (index) => buildVisitVitalSign(
            id: 'vs-$index',
            name: 'Custom Vital $index',
            value: '$index',
            unit: null,
            predefinedVitalSignId: null,
          ),
        );

        await _pumpEditor(tester, entries: entries);

        expect(find.byType(VitalSignEntryCard), findsNWidgets(20));
        expect(find.text('20 vital signs documented'), findsOneWidget);
      });

      testWidgets('null unit renders value without unit suffix', (tester) async {
        await _pumpEditor(
          tester,
          entries: [
            buildVisitVitalSign(name: 'Weight', value: '70', unit: null),
          ],
        );

        expect(find.text('WEIGHT'), findsOneWidget);
        expect(find.text('70'), findsOneWidget);
      });

      testWidgets('empty unit string renders value without unit suffix', (tester) async {
        await _pumpEditor(
          tester,
          entries: [
            buildVisitVitalSign(name: 'Weight', value: '70', unit: '  '),
          ],
        );

        expect(find.text('70'), findsOneWidget);
        expect(find.textContaining('mmHg'), findsNothing);
      });

      testWidgets('very long text does not throw', (tester) async {
        final longName = 'A' * 200;
        final longValue = '9' * 200;

        await _pumpEditor(
          tester,
          entries: [
            buildVisitVitalSign(name: longName, value: longValue, unit: 'mmHg'),
          ],
        );

        expect(find.byType(VitalSignEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('duplicate ids still render distinct rows', (tester) async {
        const sharedId = 'duplicate-id';
        final entries = [
          buildVisitVitalSign(id: sharedId, name: 'Alpha', value: '1'),
          buildVisitVitalSign(id: sharedId, name: 'Beta', value: '2'),
        ];

        await _pumpEditor(tester, entries: entries);

        expect(find.byType(VitalSignEntryCard), findsNWidgets(2));
        expect(find.text('ALPHA'), findsOneWidget);
        expect(find.text('BETA'), findsOneWidget);
      });
    });

    group('invalid state:', () {
      testWidgets('empty catalog hides Add even when canEdit is true', (tester) async {
        await _pumpEditor(tester, entries: const [], catalog: const []);

        expect(find.text('No vital signs recorded yet.'), findsOneWidget);
        expect(find.text('Add vital sign'), findsNothing);
      });

      testWidgets('all catalog predefined ids used hides Add another', (tester) async {
        final entries = [
          buildVisitVitalSign(id: 'vs-1', name: 'Blood Pressure', predefinedVitalSignId: 'vs-bp'),
          buildVisitVitalSign(id: 'vs-2', name: 'Heart Rate', predefinedVitalSignId: 'vs-hr'),
          buildVisitVitalSign(id: 'vs-3', name: 'Temperature', predefinedVitalSignId: 'vs-temp'),
        ];

        await _pumpEditor(tester, entries: entries, catalog: _catalog);

        expect(find.text('Add another vital sign'), findsNothing);
      });
    });
  });
}
