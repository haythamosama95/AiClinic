import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_widget_test_harness.dart';

Future<void> _pumpPicker(
  WidgetTester tester, {
  required PatientListItem? value,
  required ValueChanged<PatientListItem?> onChanged,
  FakePatientRepository? patientRepo,
  bool enabled = true,
  String? validationError,
}) async {
  await pumpPatientsSurface(
    tester,
    overrides: patientsProviderOverrides(
      patientRepo: patientRepo ?? FakePatientRepository(patients: samplePatientList(count: 3)),
    ),
    child: PatientPicker(
      branchId: testBranchAId,
      value: value,
      onChanged: onChanged,
      enabled: enabled,
      validationError: validationError,
    ),
  );
  await pumpPatientsFrames(tester);
}

void main() {
  group('PatientPicker', () {
    testWidgets('trivial: renders search combobox when nothing is selected', (tester) async {
      await _pumpPicker(tester, value: null, onChanged: (_) {});

      expect(find.byKey(const Key('patient_picker_search')), findsOneWidget);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.byKey(const Key('patient_picker_clear')), findsNothing);
    });

    testWidgets('advanced: searching invokes search use case and surfaces results', (tester) async {
      final repo = FakePatientRepository(
        patients: [
          samplePatientListItem(fullName: 'Ahmed Hassan'),
          samplePatientListItem(
            id: '22222222-2222-4222-8222-222222222222',
            fullName: 'Sara Ali',
          ),
        ],
      );

      await _pumpPicker(tester, value: null, onChanged: (_) {}, patientRepo: repo);

      await tester.enterText(find.byKey(const Key('patient_picker_search')), 'Ahmed');
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.searchCallCount, greaterThan(0));
      expect(repo.lastQuery, 'Ahmed');
      expect(find.text('Ahmed Hassan'), findsOneWidget);
    });

    testWidgets('advanced: selecting patient invokes onChanged and clear resets selection', (tester) async {
      final patient = samplePatientListItem(fullName: 'Picker Patient');
      final repo = FakePatientRepository(patients: [patient]);
      PatientListItem? selected;

      await _pumpPicker(
        tester,
        value: null,
        patientRepo: repo,
        onChanged: (value) => selected = value,
      );

      await tester.enterText(find.byKey(const Key('patient_picker_search')), 'Picker');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Picker Patient'));
      await pumpPatientsFrames(tester);

      expect(selected?.fullName, 'Picker Patient');
      expect(find.byKey(const Key('patient_picker_clear')), findsOneWidget);
      expect(find.text('Picker Patient'), findsWidgets);

      await _pumpPicker(
        tester,
        value: selected,
        patientRepo: repo,
        onChanged: (value) => selected = value,
      );

      await tester.tap(find.byKey(const Key('patient_picker_clear')));
      await pumpPatientsFrames(tester);

      expect(selected, isNull);
    });

    testWidgets('edge case: disabled state prevents clear and validation error renders', (tester) async {
      const validationError = 'Select a patient to continue.';

      await _pumpPicker(
        tester,
        value: samplePatientListItem(fullName: 'Locked Patient'),
        enabled: false,
        validationError: validationError,
        onChanged: (_) {},
      );

      expect(find.byKey(const Key('patient_picker_clear')), findsNothing);
      expect(find.text(validationError), findsOneWidget);
      expect(find.byKey(const Key('patient_picker_search')), findsNothing);
    });
  });
}
