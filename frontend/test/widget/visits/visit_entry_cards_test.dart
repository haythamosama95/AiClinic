import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_entry_card.dart';

import 'visit_widget_test_harness.dart';

Future<void> _pumpCard(WidgetTester tester, Widget card) async {
  await pumpVisitsSurface(tester, child: card);
  await pumpVisitsFrames(tester);
}

Future<void> _tapSemantics(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpVisitsFrames(tester);
}

void main() {
  group('VitalSignEntryCard', () {
    group('trivial:', () {
      testWidgets('displays label, value, and unit', (tester) async {
        await _pumpCard(
          tester,
          const VitalSignEntryCard(
            label: 'Blood Pressure',
            value: '120/80',
            unit: 'mmHg',
          ),
        );

        expect(find.text('BLOOD PRESSURE'), findsOneWidget);
        expect(find.text('120/80'), findsOneWidget);
        expect(find.textContaining('mmHg'), findsOneWidget);
      });

      testWidgets('edit and remove buttons invoke callbacks once', (tester) async {
        var editCount = 0;
        var removeCount = 0;

        await _pumpCard(
          tester,
          VitalSignEntryCard(
            label: 'Heart Rate',
            value: '72',
            unit: 'bpm',
            onEdit: () => editCount++,
            onRemove: () => removeCount++,
          ),
        );

        await _tapSemantics(tester, 'Edit Heart Rate');
        await _tapSemantics(tester, 'Remove Heart Rate');

        expect(editCount, 1);
        expect(removeCount, 1);
      });
    });

    group('advanced:', () {
      testWidgets('read-only mode hides action buttons', (tester) async {
        await _pumpCard(
          tester,
          const VitalSignEntryCard(
            label: 'Heart Rate',
            value: '72',
            canEdit: false,
          ),
        );

        expect(find.byType(AppIconButton), findsNothing);
      });

      testWidgets('null unit omits unit suffix', (tester) async {
        await _pumpCard(
          tester,
          const VitalSignEntryCard(
            label: 'Weight',
            value: '70',
          ),
        );

        expect(find.text('70'), findsOneWidget);
        expect(find.textContaining('mmHg'), findsNothing);
      });
    });

    group('edge case:', () {
      testWidgets('empty unit string omits unit suffix', (tester) async {
        await _pumpCard(
          tester,
          const VitalSignEntryCard(
            label: 'Weight',
            value: '70',
            unit: '   ',
          ),
        );

        expect(find.text('70'), findsOneWidget);
      });

      testWidgets('very long label and value do not throw', (tester) async {
        final longLabel = 'A' * 200;
        final longValue = '9' * 200;

        await _pumpCard(
          tester,
          VitalSignEntryCard(
            label: longLabel,
            value: longValue,
          ),
        );

        expect(find.byType(VitalSignEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('InvestigationEntryCard', () {
    group('trivial:', () {
      testWidgets('displays name and note', (tester) async {
        await _pumpCard(
          tester,
          const InvestigationEntryCard(
            name: 'Complete Blood Count',
            note: 'Fasting required',
          ),
        );

        expect(find.text('Complete Blood Count'), findsOneWidget);
        expect(find.text('Fasting required'), findsOneWidget);
      });

      testWidgets('edit and remove buttons invoke callbacks once', (tester) async {
        var editCount = 0;
        var removeCount = 0;

        await _pumpCard(
          tester,
          InvestigationEntryCard(
            name: 'MRI',
            note: 'Brain',
            onEdit: () => editCount++,
            onRemove: () => removeCount++,
          ),
        );

        await _tapSemantics(tester, 'Edit MRI');
        await _tapSemantics(tester, 'Remove MRI');

        expect(editCount, 1);
        expect(removeCount, 1);
      });
    });

    group('advanced:', () {
      testWidgets('read-only mode hides action buttons', (tester) async {
        await _pumpCard(
          tester,
          const InvestigationEntryCard(
            name: 'MRI',
            canEdit: false,
          ),
        );

        expect(find.byType(AppIconButton), findsNothing);
      });

      testWidgets('null note renders em dash placeholder', (tester) async {
        await _pumpCard(
          tester,
          const InvestigationEntryCard(
            name: 'MRI',
          ),
        );

        expect(find.text('—'), findsOneWidget);
      });
    });

    group('edge case:', () {
      testWidgets('empty note renders em dash placeholder', (tester) async {
        await _pumpCard(
          tester,
          const InvestigationEntryCard(
            name: 'MRI',
            note: '',
          ),
        );

        expect(find.text('—'), findsOneWidget);
      });

      testWidgets('very long name and note do not throw', (tester) async {
        await _pumpCard(
          tester,
          InvestigationEntryCard(
            name: 'Name ' * 100,
            note: 'Note ' * 100,
          ),
        );

        expect(find.byType(InvestigationEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('TreatmentPlanEntryCard', () {
    group('trivial:', () {
      testWidgets('displays medication, dosage, frequency, and duration', (tester) async {
        await _pumpCard(
          tester,
          const TreatmentPlanEntryCard(
            medicationName: 'Amoxicillin',
            dosage: '500 mg',
            frequency: 'bd',
            duration: '7d',
          ),
        );

        expect(find.text('Amoxicillin'), findsOneWidget);
        expect(find.text('500 mg'), findsOneWidget);
        expect(find.text('Twice daily'), findsOneWidget);
        expect(find.text('7 days'), findsOneWidget);
        expect(find.text('MEDICATION'), findsOneWidget);
        expect(find.text('DOSAGE'), findsOneWidget);
        expect(find.text('FREQUENCY'), findsOneWidget);
        expect(find.text('DURATION'), findsOneWidget);
      });

      testWidgets('edit and remove buttons invoke callbacks once', (tester) async {
        var editCount = 0;
        var removeCount = 0;

        await _pumpCard(
          tester,
          TreatmentPlanEntryCard(
            medicationName: 'Ibuprofen',
            onEdit: () => editCount++,
            onRemove: () => removeCount++,
          ),
        );

        await _tapSemantics(tester, 'Edit Ibuprofen');
        await _tapSemantics(tester, 'Remove Ibuprofen');

        expect(editCount, 1);
        expect(removeCount, 1);
      });
    });

    group('advanced:', () {
      testWidgets('read-only mode hides action buttons', (tester) async {
        await _pumpCard(
          tester,
          const TreatmentPlanEntryCard(
            medicationName: 'Ibuprofen',
            canEdit: false,
          ),
        );

        expect(find.byType(AppIconButton), findsNothing);
      });

      testWidgets('null optional fields render em dash placeholders', (tester) async {
        await _pumpCard(
          tester,
          const TreatmentPlanEntryCard(
            medicationName: 'Vitamin D',
          ),
        );

        expect(find.text('Vitamin D'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(3));
      });
    });

    group('edge case:', () {
      testWidgets('unknown frequency and duration codes render raw values', (tester) async {
        await _pumpCard(
          tester,
          const TreatmentPlanEntryCard(
            medicationName: 'Custom',
            frequency: 'custom-freq',
            duration: 'custom-dur',
          ),
        );

        expect(find.text('custom-freq'), findsOneWidget);
        expect(find.text('custom-dur'), findsOneWidget);
      });

      testWidgets('very long medication name does not throw', (tester) async {
        await _pumpCard(
          tester,
          TreatmentPlanEntryCard(
            medicationName: 'Med ' * 100,
          ),
        );

        expect(find.byType(TreatmentPlanEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('MedicalBackgroundEntryCard', () {
    group('trivial:', () {
      testWidgets('displays title and note', (tester) async {
        await _pumpCard(
          tester,
          const MedicalBackgroundEntryCard(
            title: 'Type 2 diabetes',
            note: 'Well controlled',
            accent: MedicalBackgroundAccent.warning,
          ),
        );

        expect(find.text('Type 2 diabetes'), findsOneWidget);
        expect(find.text('Well controlled'), findsOneWidget);
      });

      testWidgets('edit and remove buttons invoke callbacks once', (tester) async {
        var editCount = 0;
        var removeCount = 0;

        await _pumpCard(
          tester,
          MedicalBackgroundEntryCard(
            title: 'Penicillin',
            note: 'Rash',
            accent: MedicalBackgroundAccent.danger,
            onEdit: () => editCount++,
            onRemove: () => removeCount++,
          ),
        );

        await _tapSemantics(tester, 'Edit Penicillin');
        await _tapSemantics(tester, 'Remove Penicillin');

        expect(editCount, 1);
        expect(removeCount, 1);
      });
    });

    group('advanced:', () {
      testWidgets('read-only mode hides action buttons', (tester) async {
        await _pumpCard(
          tester,
          const MedicalBackgroundEntryCard(
            title: 'Penicillin',
            accent: MedicalBackgroundAccent.danger,
            canEdit: false,
          ),
        );

        expect(find.byType(AppIconButton), findsNothing);
      });

      testWidgets('null note renders em dash placeholder', (tester) async {
        await _pumpCard(
          tester,
          const MedicalBackgroundEntryCard(
            title: 'Penicillin',
            accent: MedicalBackgroundAccent.danger,
          ),
        );

        expect(find.text('—'), findsOneWidget);
      });
    });

    group('edge case:', () {
      testWidgets('empty strings do not throw', (tester) async {
        await _pumpCard(
          tester,
          const MedicalBackgroundEntryCard(
            title: '',
            note: '',
            accent: MedicalBackgroundAccent.info,
          ),
        );

        expect(find.byType(MedicalBackgroundEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('very long title and note do not throw', (tester) async {
        await _pumpCard(
          tester,
          MedicalBackgroundEntryCard(
            title: 'Title ' * 100,
            note: 'Note ' * 100,
            accent: MedicalBackgroundAccent.info,
          ),
        );

        expect(find.byType(MedicalBackgroundEntryCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
