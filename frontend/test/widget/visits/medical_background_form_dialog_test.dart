import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_form_dialog.dart';

import 'visit_widget_test_harness.dart';

/// Mirrors [VisitMedicalBackgroundEditor] category specs for dialog copy.
class _MedicalBackgroundSpec {
  const _MedicalBackgroundSpec({
    required this.dialogTitle,
    required this.dialogDescription,
    required this.itemLabel,
    required this.noteLabel,
    required this.itemPlaceholder,
    required this.notePlaceholder,
    required this.editDialogTitle,
  });

  final String dialogTitle;
  final String dialogDescription;
  final String itemLabel;
  final String noteLabel;
  final String itemPlaceholder;
  final String notePlaceholder;
  final String editDialogTitle;
}

const _conditionSpec = _MedicalBackgroundSpec(
  dialogTitle: 'Add chronic condition',
  dialogDescription: 'Record a condition and any context relevant to this visit.',
  itemLabel: 'Condition',
  noteLabel: 'Clinical note',
  itemPlaceholder: 'e.g. Type 2 diabetes',
  notePlaceholder: 'e.g. Diagnosed 2019 · well controlled on metformin…',
  editDialogTitle: 'Edit chronic condition',
);

const _allergySpec = _MedicalBackgroundSpec(
  dialogTitle: 'Add allergy',
  dialogDescription: 'Record an allergen and describe the reaction for this encounter.',
  itemLabel: 'Allergy',
  noteLabel: 'Reaction note',
  itemPlaceholder: 'e.g. Penicillin',
  notePlaceholder: 'e.g. Anaphylaxis · avoid all beta-lactams…',
  editDialogTitle: 'Edit allergy',
);

const _medicationSpec = _MedicalBackgroundSpec(
  dialogTitle: 'Add medication',
  dialogDescription: 'Record a medication and how the patient is taking it.',
  itemLabel: 'Medication',
  noteLabel: 'Dosing note',
  itemPlaceholder: 'e.g. Metformin',
  notePlaceholder: 'e.g. 500 mg twice daily · good adherence…',
  editDialogTitle: 'Edit medication',
);

Future<void> _openMedicalBackgroundDialog(
  WidgetTester tester, {
  required _MedicalBackgroundSpec spec,
  String? initialTitle,
  String? initialNote,
  required void Function(Future<MedicalBackgroundFormResult?> future) onShow,
}) async {
  await pumpVisitsSurface(
    tester,
    child: Builder(
      builder: (context) => TextButton(
        onPressed: () {
          onShow(
            MedicalBackgroundFormDialog.show(
              context,
<<<<<<< HEAD
              dialogTitle: spec.dialogTitle,
=======
              dialogTitle: initialTitle != null ? spec.editDialogTitle : spec.dialogTitle,
>>>>>>> master
              dialogDescription: spec.dialogDescription,
              itemLabel: spec.itemLabel,
              noteLabel: spec.noteLabel,
              itemPlaceholder: spec.itemPlaceholder,
              notePlaceholder: spec.notePlaceholder,
              initialTitle: initialTitle,
              initialNote: initialNote,
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

Finder _titleField() {
  return find.descendant(
    of: find.byType(MedicalBackgroundFormDialog),
    matching: find.byType(TextField),
  ).first;
}

Finder _noteField() {
  return find.descendant(
    of: find.byType(MedicalBackgroundFormDialog),
    matching: find.byType(TextField),
  ).last;
}

void main() {
  for (final spec in [_conditionSpec, _allergySpec, _medicationSpec]) {
    group('MedicalBackgroundFormDialog — ${spec.itemLabel}', () {
      testWidgets('trivial: opens with configured labels and actions', (tester) async {
        await _openMedicalBackgroundDialog(tester, spec: spec, onShow: (_) {});

        expect(find.text(spec.dialogTitle), findsOneWidget);
        expect(find.text(spec.dialogDescription), findsOneWidget);
        expect(find.text(spec.itemLabel), findsOneWidget);
        expect(find.text(spec.noteLabel), findsOneWidget);
        expect(find.text('Optional'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Add'), findsOneWidget);
        expect(find.byType(MedicalBackgroundFormDialog), findsOneWidget);
      });

      testWidgets('advanced: valid submit returns title and note', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.enterText(_titleField(), 'Entry title');
        await tester.pump();
        await tester.enterText(_noteField(), 'Entry note');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Add'));
        await tester.pump();

        expect(captured?.title, 'Entry title');
        expect(captured?.note, 'Entry note');
      });

      testWidgets('invalid state: empty title shows validation message', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.tap(find.widgetWithText(AppButton, 'Add'));
        await tester.pump();

        expect(find.text('Enter a name to continue.'), findsOneWidget);
        expect(captured, isNull);
      });

      testWidgets('invalid state: whitespace-only title shows validation message', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.enterText(_titleField(), '   ');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Add'));
        await tester.pump();

        expect(find.text('Enter a name to continue.'), findsOneWidget);
        expect(captured, isNull);
      });

      testWidgets('edge case: empty note is returned as null', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.enterText(_titleField(), 'Entry title');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Add'));
        await tester.pump();

        expect(captured?.note, isNull);
      });

      testWidgets('edge case: trims title and note whitespace on submit', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.enterText(_titleField(), '  Trimmed title  ');
        await tester.pump();
        await tester.enterText(_noteField(), '  Trimmed note  ');
        await tester.pump();
        await tester.tap(find.widgetWithText(AppButton, 'Add'));
        await tester.pump();

        expect(captured?.title, 'Trimmed title');
        expect(captured?.note, 'Trimmed note');
      });

      testWidgets('trivial: cancel pops with null', (tester) async {
        MedicalBackgroundFormResult? captured;
        await _openMedicalBackgroundDialog(
          tester,
          spec: spec,
          onShow: (future) async => captured = await future,
        );

        await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(captured, isNull);
      });
    });
  }

  group('MedicalBackgroundFormDialog — edit mode', () {
    testWidgets('trivial: pre-fills title and note and shows Save changes', (tester) async {
      await _openMedicalBackgroundDialog(
        tester,
        spec: _conditionSpec,
        initialTitle: 'Type 2 diabetes',
        initialNote: 'Well controlled',
        onShow: (_) {},
      );

      expect(find.text(_conditionSpec.editDialogTitle), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      final titleWidget = tester.widget<TextField>(_titleField());
      final noteWidget = tester.widget<TextField>(_noteField());
      expect(titleWidget.controller?.text, 'Type 2 diabetes');
      expect(noteWidget.controller?.text, 'Well controlled');
    });
  });

  group('MedicalBackgroundFormDialog — allergy reaction note', () {
    testWidgets('advanced: allergy severity is captured as free-text reaction note', (tester) async {
      MedicalBackgroundFormResult? captured;
      await _openMedicalBackgroundDialog(
        tester,
        spec: _allergySpec,
        onShow: (future) async => captured = await future,
      );

      await tester.enterText(_titleField(), 'Penicillin');
      await tester.pump();
      await tester.enterText(_noteField(), 'Severe');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Add'));
      await tester.pump();

      expect(captured?.title, 'Penicillin');
      expect(captured?.note, 'Severe');
      expect(find.text('Mild'), findsNothing);
      expect(find.text('Life-threatening'), findsNothing);
    });
  });

  group('MedicalBackgroundFormDialog — dismissal', () {
    testWidgets('edge case: barrier tap dismisses with null', (tester) async {
      MedicalBackgroundFormResult? captured;
      await _openMedicalBackgroundDialog(
        tester,
        spec: _conditionSpec,
        onShow: (future) async => captured = await future,
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured, isNull);
    });
  });
}
