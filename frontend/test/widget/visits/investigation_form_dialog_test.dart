import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
<<<<<<< HEAD
=======
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
>>>>>>> master
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_form_dialog.dart';

import '../../support/visit_rpc_test_client.dart';
import 'visit_widget_test_harness.dart';

const _catalogInvestigationId = 'iiiiiiii-iiii-4iii-8iii-iiiiiiiiiiii';

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
<<<<<<< HEAD
=======
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tapDialogButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
>>>>>>> master
}

Future<void> _openInvestigationDialog(
  WidgetTester tester, {
  required Set<String> usedInvestigationIds,
  VisitInvestigation? editingEntry,
  VisitRpcTestClient? rpcClient,
  required void Function(Future<InvestigationFormResult?> future) onShow,
}) async {
  final client = rpcClient ?? VisitRpcTestClient();
  await pumpVisitsSurface(
    tester,
    overrides: visitsProviderOverrides(rpcClient: client),
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () {
          onShow(
            InvestigationFormDialog.show(
              context,
              usedInvestigationIds: usedInvestigationIds,
              editingEntry: editingEntry,
            ),
          );
        },
        child: const Text('open-dialog'),
      ),
    ),
  );
  await tester.tap(find.text('open-dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('InvestigationFormDialog — create mode', () {
    testWidgets('trivial: opens with title, fields, and actions', (tester) async {
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (_) {},
      );

      expect(find.text('Add investigation'), findsWidgets);
      expect(
        find.text('Choose a diagnostic test and add any relevant clinical notes.'),
        findsOneWidget,
      );
      expect(find.text('Investigation'), findsOneWidget);
      expect(find.text('Clinical note'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Add investigation'), findsOneWidget);
      expect(find.byType(InvestigationFormDialog), findsOneWidget);
    });

    testWidgets('advanced: search RPC populates combobox results', (tester) async {
      final client = VisitRpcTestClient();
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        rpcClient: client,
        onShow: (_) {},
      );

      final field = find.descendant(
        of: find.bySemanticsIdentifier('investigation-type'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'blood');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Complete Blood Count'), findsOneWidget);
      expect(client.rpcCalls.any((call) => call.fn == 'search_investigations'), isTrue);
    });

    testWidgets('advanced: selecting search result and submitting returns populated result', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'investigation-type',
        query: 'blood',
        optionLabel: 'Complete Blood Count',
      );

      final noteField = find.descendant(
        of: find.byType(InvestigationFormDialog),
        matching: find.byType(TextField),
      ).last;
      await tester.enterText(noteField, 'Fasting sample');
      await tester.pump();

<<<<<<< HEAD
      await tester.tap(find.widgetWithText(AppButton, 'Add investigation'));
      await tester.pump();
=======
      await _tapDialogButton(tester, 'Add investigation');
>>>>>>> master
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNotNull);
      expect(captured!.name, 'Complete Blood Count');
      expect(captured!.investigationId, _catalogInvestigationId);
      expect(captured!.note, 'Fasting sample');
    });

    testWidgets('edge case: empty note is returned as null', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'investigation-type',
        query: 'blood',
        optionLabel: 'Complete Blood Count',
      );
<<<<<<< HEAD
      await tester.tap(find.widgetWithText(AppButton, 'Add investigation'));
      await tester.pump();
=======
      await _tapDialogButton(tester, 'Add investigation');
>>>>>>> master

      expect(captured?.note, isNull);
    });

    testWidgets('edge case: trims note whitespace on submit', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

      await _tapComboboxOption(
        tester,
        comboboxId: 'investigation-type',
        query: 'blood',
        optionLabel: 'Complete Blood Count',
      );

      final noteField = find.descendant(
        of: find.byType(InvestigationFormDialog),
        matching: find.byType(TextField),
      ).last;
      await tester.enterText(noteField, '  urgent  ');
      await tester.pump();
<<<<<<< HEAD
      await tester.tap(find.widgetWithText(AppButton, 'Add investigation'));
      await tester.pump();
=======
      await _tapDialogButton(tester, 'Add investigation');
>>>>>>> master

      expect(captured?.note, 'urgent');
    });
  });

  group('InvestigationFormDialog — edit mode', () {
    testWidgets('trivial: pre-fills investigation and note from editing entry', (tester) async {
      final editing = buildVisitInvestigation(
        investigationId: _catalogInvestigationId,
        name: 'Complete Blood Count',
        note: 'Rule out infection',
      );

      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: {_catalogInvestigationId},
        editingEntry: editing,
        onShow: (_) {},
      );

      expect(find.text('Edit investigation'), findsOneWidget);
      expect(
        find.text('Update the test or add clinical context for this order.'),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Complete Blood Count'), findsWidgets);

      final noteField = find.descendant(
        of: find.byType(InvestigationFormDialog),
        matching: find.byType(TextField),
      ).last;
      final noteWidget = tester.widget<TextField>(noteField);
      expect(noteWidget.controller?.text, 'Rule out infection');
    });
  });

  group('InvestigationFormDialog — validation', () {
    testWidgets('invalid state: submit without selection shows validation message', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

      await tester.tap(find.widgetWithText(AppButton, 'Add investigation'));
      await tester.pump();

      expect(find.text('Select an investigation.'), findsOneWidget);
      expect(captured, isNull);
      expect(find.byType(InvestigationFormDialog), findsOneWidget);
    });
  });

  group('InvestigationFormDialog — combobox search', () {
    testWidgets('edge case: empty RPC results show no-matches message', (tester) async {
      final client = VisitRpcTestClient()
        ..rpcResults['search_investigations'] = {
          'success': true,
          'data': {'items': <Map<String, dynamic>>[]},
        };

      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        rpcClient: client,
        onShow: (_) {},
      );

      final field = find.descendant(
        of: find.bySemanticsIdentifier('investigation-type'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('No matches for "zzzz"'), findsOneWidget);
    });

    testWidgets('advanced: debounce delays search RPC until debounce elapses', (tester) async {
      final client = VisitRpcTestClient();
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        rpcClient: client,
        onShow: (_) {},
      );

      final field = find.descendant(
        of: find.bySemanticsIdentifier('investigation-type'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'blood');
      await tester.pump(const Duration(milliseconds: 100));

      expect(client.rpcCalls.where((call) => call.fn == 'search_investigations'), isEmpty);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(client.rpcCalls.any((call) => call.fn == 'search_investigations'), isTrue);
    });

    testWidgets('regression: already-used catalog item is disabled with reason', (tester) async {
      final client = VisitRpcTestClient();
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: {_catalogInvestigationId},
        rpcClient: client,
        onShow: (_) {},
      );

      final field = find.descendant(
        of: find.bySemanticsIdentifier('investigation-type'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'blood');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Already added'), findsOneWidget);
    });
  });

  group('InvestigationFormDialog — dismissal', () {
    testWidgets('trivial: cancel pops with null', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

<<<<<<< HEAD
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
=======
      final cancelButton = find.widgetWithText(AppButton, 'Cancel');
      await tester.ensureVisible(cancelButton);
      await tester.pump();
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
>>>>>>> master

      expect(captured, isNull);
      expect(find.byType(InvestigationFormDialog), findsNothing);
    });

    testWidgets('edge case: barrier tap dismisses with null', (tester) async {
      InvestigationFormResult? captured;
      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        onShow: (future) async => captured = await future,
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNull);
    });
  });

  group('InvestigationFormDialog — RPC failure', () {
    testWidgets('invalid state: search RPC failure throws uncaught async error', (tester) async {
      final client = VisitRpcTestClient()
        ..rpcResults['search_investigations'] = {
          'success': false,
          'error_code': 'SEARCH_FAILED',
          'error_message': 'Could not search investigations.',
        };

      await _openInvestigationDialog(
        tester,
        usedInvestigationIds: const {},
        rpcClient: client,
        onShow: (_) {},
      );

      final field = find.descendant(
        of: find.bySemanticsIdentifier('investigation-type'),
        matching: find.byType(TextField),
      );
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'blood');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      final exception = tester.takeException();
<<<<<<< HEAD
      expect(exception, isNotNull);
=======
      expect(exception, isNull);
>>>>>>> master
      expect(find.text('Could not search investigations.'), findsNothing);
    });
  });
}
