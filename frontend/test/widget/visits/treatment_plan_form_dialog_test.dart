import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_options.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_form_dialog.dart';

import '../../support/visit_rpc_test_client.dart';
import 'visit_widget_test_harness.dart';

const _catalogMedicationId = 'mmmmmmmm-mmmm-4mmm-8mmm-mmmmmmmmmmmm';

Future<void> _tapAppSelectOption(WidgetTester tester, String selectId, String optionLabel) async {
  final select = find.bySemanticsIdentifier(selectId);
  await tester.ensureVisible(select);
  await tester.pump();
  await tester.tap(select);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

Future<void> _expectSelectOptionLabelsVisible(WidgetTester tester, Iterable<String> labels) async {
  final scrollable = find.descendant(
    of: find.byType(Overlay),
    matching: find.byType(Scrollable),
  ).last;

  for (final label in labels) {
    final optionFinder = find.text(label);
    await tester.scrollUntilVisible(
      optionFinder,
      50,
      scrollable: scrollable,
    );
    await tester.pump();
    expect(optionFinder, findsOneWidget);
  }
}

Future<void> _tapComboboxOption(
  WidgetTester tester, {
  required String comboboxId,
  required String query,
  required String optionLabel,
}) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(comboboxId),
    matching: find.byType(TextField),
  );
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.tap(find.text(optionLabel).last);
  await tester.pump();
}

Future<void> _openTreatmentPlanDialog(
  WidgetTester tester, {
  TreatmentPlanItem? editingEntry,
  VisitRpcTestClient? rpcClient,
  required void Function(Future<TreatmentPlanFormResult?> future) onShow,
}) async {
  final client = rpcClient ?? VisitRpcTestClient();
  await pumpVisitsSurface(
    tester,
    overrides: visitsProviderOverrides(rpcClient: client),
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () {
          onShow(TreatmentPlanFormDialog.show(context, editingEntry: editingEntry));
        },
        child: const Text('open-dialog'),
      ),
    ),
  );
  await tester.tap(find.text('open-dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _dosageField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('treatment-dosage'),
    matching: find.byType(TextField),
  );
}

void main() {
  group('TreatmentPlanFormDialog — create mode', () {
    testWidgets('trivial: opens with title, fields, and actions', (tester) async {
      await _openTreatmentPlanDialog(tester, onShow: (_) {});

      expect(find.text('Add prescription'), findsWidgets);
      expect(
        find.text('Prescribe a medication with dosage, frequency, and duration.'),
        findsOneWidget,
      );
      expect(find.text('Medication'), findsOneWidget);
      expect(find.text('Dosage'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Add prescription'), findsOneWidget);
      expect(find.byType(TreatmentPlanFormDialog), findsOneWidget);
    });

    testWidgets('advanced: valid submit returns all result fields', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'treatment-medication',
        query: 'amox',
        optionLabel: 'Amoxicillin',
      );
      await tester.enterText(_dosageField(), '500 mg');
      await tester.pump();
      await _tapAppSelectOption(tester, 'treatment-frequency-select', 'Twice daily');
      await _tapAppSelectOption(tester, 'treatment-duration-select', '7 days');

      await _tapDialogButton(tester, 'Add prescription');
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNotNull);
      expect(captured!.medicationName, 'Amoxicillin');
      expect(captured!.medicationId, _catalogMedicationId);
      expect(captured!.dosage, '500 mg');
      expect(captured!.frequency, 'bd');
      expect(captured!.duration, '7d');
    });

    testWidgets('edge case: trims dosage whitespace on submit', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'treatment-medication',
        query: 'amox',
        optionLabel: 'Amoxicillin',
      );
      await tester.enterText(_dosageField(), '  250 mg  ');
      await tester.pump();
      await _tapAppSelectOption(tester, 'treatment-frequency-select', 'Once daily');
      await _tapAppSelectOption(tester, 'treatment-duration-select', '5 days');
      await _tapDialogButton(tester, 'Add prescription');

      expect(captured?.dosage, '250 mg');
    });
  });

  group('TreatmentPlanFormDialog — edit mode', () {
    testWidgets('trivial: pre-fills medication, dosage, frequency, and duration', (tester) async {
      final editing = buildVisitTreatmentPlanItem(
        medicationName: 'Amoxicillin',
        medicationId: _catalogMedicationId,
        dosage: '500 mg',
        frequency: 'bd',
        duration: '7d',
      );

      await _openTreatmentPlanDialog(tester, editingEntry: editing, onShow: (_) {});

      expect(find.text('Edit prescription'), findsOneWidget);
      expect(
        find.text('Update medication, dosage, frequency, or duration.'),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Amoxicillin'), findsWidgets);
      expect(find.text('Twice daily'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);

      final dosageWidget = tester.widget<TextField>(_dosageField());
      expect(dosageWidget.controller?.text, '500 mg');
    });
  });

  group('TreatmentPlanFormDialog — validation', () {
    testWidgets('invalid state: empty submit shows all required field messages', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Add prescription'));
      await tester.pump();

      expect(find.text('Select a medication.'), findsOneWidget);
      expect(find.text('Enter the dosage.'), findsOneWidget);
      expect(find.text('Select a frequency.'), findsOneWidget);
      expect(find.text('Select a duration.'), findsOneWidget);
      expect(captured, isNull);
    });

    testWidgets('invalid state: whitespace-only dosage shows validation message', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'treatment-medication',
        query: 'amox',
        optionLabel: 'Amoxicillin',
      );
      await tester.enterText(_dosageField(), '   ');
      await tester.pump();
      await _tapAppSelectOption(tester, 'treatment-frequency-select', 'Once daily');
      await _tapAppSelectOption(tester, 'treatment-duration-select', '3 days');
      await _tapDialogButton(tester, 'Add prescription');

      expect(find.text('Enter the dosage.'), findsOneWidget);
      expect(captured, isNull);
    });
  });

  group('TreatmentPlanFormDialog — combobox search', () {
    testWidgets('advanced: medication search calls RPC and renders result', (tester) async {
      final client = VisitRpcTestClient();
      await _openTreatmentPlanDialog(tester, rpcClient: client, onShow: (_) {});

      final field = find.descendant(
        of: find.bySemanticsIdentifier('treatment-medication'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'amox');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Amoxicillin'), findsOneWidget);
      expect(client.rpcCalls.any((call) => call.fn == 'search_medications'), isTrue);
    });

    testWidgets('edge case: empty medication search shows no-matches message', (tester) async {
      final client = VisitRpcTestClient()
        ..rpcResults['search_medications'] = {
          'success': true,
          'data': {'items': <Map<String, dynamic>>[]},
        };

      await _openTreatmentPlanDialog(tester, rpcClient: client, onShow: (_) {});

      final field = find.descendant(
        of: find.bySemanticsIdentifier('treatment-medication'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('No matches for "zzzz"'), findsOneWidget);
    });

    testWidgets('advanced: debounce delays medication search RPC', (tester) async {
      final client = VisitRpcTestClient();
      await _openTreatmentPlanDialog(tester, rpcClient: client, onShow: (_) {});

      final field = find.descendant(
        of: find.bySemanticsIdentifier('treatment-medication'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'amox');
      await tester.pump(const Duration(milliseconds: 100));

      expect(client.rpcCalls.where((call) => call.fn == 'search_medications'), isEmpty);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(client.rpcCalls.any((call) => call.fn == 'search_medications'), isTrue);
    });
  });

  group('TreatmentPlanFormDialog — select options', () {
    testWidgets('trivial: frequency select offers treatmentFrequencyOptions labels', (tester) async {
      await _openTreatmentPlanDialog(tester, onShow: (_) {});

      final frequencySelect = find.bySemanticsIdentifier('treatment-frequency-select');
      await tester.ensureVisible(frequencySelect);
      await tester.pump();
      await tester.tap(frequencySelect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await _expectSelectOptionLabelsVisible(
        tester,
        treatmentFrequencyOptions.map((option) => option.label),
      );
    });

    testWidgets('trivial: duration select offers treatmentDurationOptions labels', (tester) async {
      await _openTreatmentPlanDialog(tester, onShow: (_) {});

      final durationSelect = find.bySemanticsIdentifier('treatment-duration-select');
      await tester.ensureVisible(durationSelect);
      await tester.pump();
      await tester.tap(durationSelect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await _expectSelectOptionLabelsVisible(
        tester,
        treatmentDurationOptions.map((option) => option.label),
      );
    });
  });

  group('TreatmentPlanFormDialog — dismissal', () {
    testWidgets('trivial: cancel pops with null', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await _tapDialogButton(tester, 'Cancel');
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.byType(TreatmentPlanFormDialog), findsNothing);
    });

    testWidgets('edge case: barrier tap dismisses with null', (tester) async {
      TreatmentPlanFormResult? captured;
      await _openTreatmentPlanDialog(
        tester,
        onShow: (future) async => captured = await future,
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNull);
    });
  });

  group('TreatmentPlanFormDialog — RPC failure', () {
    testWidgets('invalid state: medication search RPC failure throws uncaught async error', (tester) async {
      final client = VisitRpcTestClient()
        ..rpcResults['search_medications'] = {
          'success': false,
          'error_code': 'SEARCH_FAILED',
          'error_message': 'Could not search medications.',
        };

      await _openTreatmentPlanDialog(tester, rpcClient: client, onShow: (_) {});

      final field = find.descendant(
        of: find.bySemanticsIdentifier('treatment-medication'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'amox');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNull);
      expect(find.text('Could not search medications.'), findsNothing);
    });
  });
}
