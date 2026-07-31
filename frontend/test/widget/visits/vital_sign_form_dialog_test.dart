import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_form_dialog.dart';

import 'visit_widget_test_harness.dart';

const _bloodPressureId = 'vvvvvvvv-vvvv-4vvv-8vvv-vvvvvvvvvvvv';
const _heartRateId = 'hhhhhhhh-hhhh-4hhh-8hhh-hhhhhhhhhhhh';

final _vitalSignCatalog = <CatalogItem>[
  const CatalogItem(id: _bloodPressureId, name: 'Blood Pressure', defaultUnit: 'mmHg'),
  const CatalogItem(id: _heartRateId, name: 'Heart Rate', defaultUnit: 'bpm'),
];

Future<void> _tapAppSelectOption(WidgetTester tester, Key selectKey, String optionLabel) async {
  await tester.tap(find.byKey(selectKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
}

Future<VitalSignFormResult?> _pumpAndOpenDialog(
  WidgetTester tester, {
  required Set<String> usedPredefinedIds,
  VisitVitalSign? editingEntry,
}) async {
  VitalSignFormResult? captured;

  await pumpVisitsSurface(
    tester,
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          captured = await VitalSignFormDialog.show(
            context,
            catalog: _vitalSignCatalog,
            usedPredefinedIds: usedPredefinedIds,
            editingEntry: editingEntry,
          );
        },
        child: const Text('open-dialog'),
      ),
    ),
  );

  await tester.tap(find.text('open-dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  return captured;
}

Finder _valueField(WidgetTester tester) {
  return find.descendant(
    of: find.byType(VitalSignFormDialog),
    matching: find.byType(TextField),
  );
}

void main() {
  group('VitalSignFormDialog — create mode', () {
    testWidgets('trivial: opens with title, fields, and actions', (tester) async {
      await _pumpAndOpenDialog(tester, usedPredefinedIds: const {});

      expect(find.text('Record vital sign'), findsOneWidget);
      expect(
        find.text('Choose the measurement type and enter the value taken during this encounter.'),
        findsOneWidget,
      );
      expect(find.text('Vital sign'), findsOneWidget);
      expect(find.text('Value (mmHg)'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Add vital sign'), findsOneWidget);
      expect(find.byType(VitalSignFormDialog), findsOneWidget);
    });

    testWidgets('trivial: pre-selects first available catalog type', (tester) async {
      await _pumpAndOpenDialog(tester, usedPredefinedIds: const {});

      expect(find.text('Blood Pressure'), findsWidgets);
      expect(find.text('Value (mmHg)'), findsOneWidget);
    });

    testWidgets('advanced: valid submit returns populated result', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(_valueField(tester), '120/80');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNotNull);
      expect(captured!.predefinedVitalSignId, _bloodPressureId);
      expect(captured!.name, 'Blood Pressure');
      expect(captured!.value, '120/80');
      expect(captured!.unit, 'mmHg');
      expect(find.byType(VitalSignFormDialog), findsNothing);
    });

    testWidgets('edge case: trims whitespace from value on submit', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(_valueField(tester), '  98  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
      await tester.pump();

      expect(captured?.value, '98');
    });

    testWidgets('advanced: accepts non-numeric value without format validation', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(_valueField(tester), 'not-a-number');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
      await tester.pump();

      expect(captured?.value, 'not-a-number');
      expect(find.text('Enter the measured value.'), findsNothing);
    });
  });

  group('VitalSignFormDialog — edit mode', () {
    testWidgets('trivial: pre-fills type and value from editing entry', (tester) async {
      final editing = buildVisitVitalSign(
        predefinedVitalSignId: _bloodPressureId,
        name: 'Blood Pressure',
        value: '118/76',
        unit: 'mmHg',
      );

      await _pumpAndOpenDialog(
        tester,
        usedPredefinedIds: {_bloodPressureId},
        editingEntry: editing,
      );

      expect(find.text('Edit vital sign'), findsOneWidget);
      expect(
        find.text('Update the measurement type or value for this entry.'),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Blood Pressure'), findsWidgets);

      final field = tester.widget<TextField>(_valueField(tester));
      expect(field.controller?.text, '118/76');
    });

    testWidgets('advanced: edit submit preserves catalog unit in result', (tester) async {
      VitalSignFormResult? captured;
      final editing = buildVisitVitalSign(
        predefinedVitalSignId: _bloodPressureId,
        value: '118/76',
      );

      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: {_bloodPressureId},
                editingEntry: editing,
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(_valueField(tester), '122/82');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
      await tester.pump();

      expect(captured?.predefinedVitalSignId, _bloodPressureId);
      expect(captured?.name, 'Blood Pressure');
      expect(captured?.value, '122/82');
      expect(captured?.unit, 'mmHg');
    });

    testWidgets('edge case: changing type clears value when different from editing entry', (tester) async {
      final editing = buildVisitVitalSign(
        predefinedVitalSignId: _bloodPressureId,
        value: '118/76',
      );

      await _pumpAndOpenDialog(
        tester,
        usedPredefinedIds: {_bloodPressureId},
        editingEntry: editing,
      );

      await _tapAppSelectOption(tester, const Key('vital-sign-type-select'), 'Heart Rate');
      await tester.pump();

      final field = tester.widget<TextField>(_valueField(tester));
      expect(field.controller?.text, isEmpty);
      expect(find.text('Value (bpm)'), findsOneWidget);
    });
  });

  group('VitalSignFormDialog — validation', () {
    testWidgets('invalid state: empty value shows validation message', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
      await tester.pump();

      expect(find.text('Enter the measured value.'), findsOneWidget);
      expect(captured, isNull);
      expect(find.byType(VitalSignFormDialog), findsOneWidget);
    });

    testWidgets('invalid state: whitespace-only value shows validation message', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(_valueField(tester), '   ');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add vital sign'));
      await tester.pump();

      expect(find.text('Enter the measured value.'), findsOneWidget);
      expect(captured, isNull);
    });
  });

  group('VitalSignFormDialog — dismissal', () {
    testWidgets('trivial: cancel pops with null', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNull);
      expect(find.byType(VitalSignFormDialog), findsNothing);
    });

    testWidgets('edge case: barrier tap dismisses with null', (tester) async {
      VitalSignFormResult? captured;
      await pumpVisitsSurface(
        tester,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await VitalSignFormDialog.show(
                context,
                catalog: _vitalSignCatalog,
                usedPredefinedIds: const {},
              );
            },
            child: const Text('open-dialog'),
          ),
        ),
      );
      await tester.tap(find.text('open-dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNull);
      expect(find.byType(VitalSignFormDialog), findsNothing);
    });
  });
}
