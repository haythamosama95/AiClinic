import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/patients/domain/patient_field_validation.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_form_fields.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';

import 'patients_widget_test_harness.dart';

const _fieldIds = <String>[
  'fullName',
  'dob',
  'gender',
  'phone',
  'maritalStatus',
  'notes',
];

class _FormFieldsHarness extends StatefulWidget {
  const _FormFieldsHarness({
    this.branchName,
    this.fieldIdPrefix = 'add-patient',
    this.errors = PatientFormErrors.empty,
  });

  final String? branchName;
  final String fieldIdPrefix;
  final PatientFormErrors errors;

  @override
  State<_FormFieldsHarness> createState() => _FormFieldsHarnessState();
}

class _FormFieldsHarnessState extends State<_FormFieldsHarness> {
  PatientRegistrationForm _values = PatientRegistrationForm.empty;
  var _submitCount = 0;

  void _onFieldChange(String key, Object? value) {
    setState(() {
      _values = switch (key) {
        'fullName' => _values.copyWith(fullName: value as String),
        'phone' => _values.copyWith(phone: value as String),
        'dateOfBirth' => _values.copyWith(dateOfBirth: value as DateTime?),
        'notes' => _values.copyWith(notes: value as String),
        _ => _values,
      };
    });
  }

  void _onSubmit() {
    setState(() => _submitCount++);
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = _values.fullName.trim();
    return SingleChildScrollView(
      child: Column(
        children: [
          AddPatientFormFields(
            values: _values,
            errors: widget.errors,
            trimmedName: trimmedName,
            showPreview: trimmedName.length >= 2,
            reducedMotion: true,
            branchName: widget.branchName,
            fieldIdPrefix: widget.fieldIdPrefix,
            onSubmit: _onSubmit,
            onFieldChange: _onFieldChange,
          ),
          Text('submit-count:$_submitCount'),
        ],
      ),
    );
  }
}

Finder _textFieldFor(String fieldIdPrefix, String field) {
  return find.descendant(
    of: find.bySemanticsIdentifier('$fieldIdPrefix-$field'),
    matching: find.byType(TextField),
  );
}

void main() {
  group('AddPatientFormFields', () {
    testWidgets('trivial: all six fields render with semantics identifiers', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(),
      );
      await pumpPatientsFrames(tester);

      for (final field in _fieldIds) {
        expect(find.bySemanticsIdentifier('add-patient-$field'), findsOneWidget);
      }
    });

    testWidgets('advanced: typing name updates preview past minimum length', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(),
      );
      await pumpPatientsFrames(tester);

      expect(find.byKey(const ValueKey<String>('identity-preview-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('identity-preview')), findsNothing);

      await tester.enterText(_textFieldFor('add-patient', 'fullName'), 'A');
      await pumpPatientsFrames(tester);

      expect(find.byKey(const ValueKey<String>('identity-preview-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('identity-preview')), findsNothing);

      await tester.enterText(_textFieldFor('add-patient', 'fullName'), 'Ab');
      await pumpPatientsFrames(tester);

      expect(find.byKey(const ValueKey<String>('identity-preview')), findsOneWidget);
      expect(find.text('Ab'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('identity-preview-empty')), findsNothing);
    });

    testWidgets('advanced: per-field validation messages render from source', (tester) async {
      final errors = PatientFormErrors(
        fullName: "Enter the patient's full name.",
        phone: PatientFieldValidation.validateMobileNumber(''),
        dateOfBirth: 'Date of birth is invalid.',
        gender: 'Gender is invalid.',
        maritalStatus: 'Marital state is invalid.',
        notes: 'Notes are too long.',
      );

      await pumpPatientsDialogShell(
        tester,
        home: _FormFieldsHarness(errors: errors),
      );
      await pumpPatientsFrames(tester);

      expect(find.text(errors.fullName!), findsOneWidget);
      expect(find.text('Mobile number is required.'), findsOneWidget);
      expect(find.text(errors.dateOfBirth!), findsOneWidget);
      expect(find.text(errors.gender!), findsOneWidget);
      expect(find.text(errors.maritalStatus!), findsOneWidget);
      expect(find.text(errors.notes!), findsOneWidget);
    });

    testWidgets('advanced: form-level error renders in live region', (tester) async {
      const formError = 'Could not register the patient. Try again.';

      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(
          errors: PatientFormErrors(form: formError),
        ),
      );
      await pumpPatientsFrames(tester);

      expect(find.text(formError), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(formError),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && (widget.properties.liveRegion ?? false),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('advanced: branch banner uses supplied branch name', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(branchName: 'Downtown Clinic'),
      );
      await pumpPatientsFrames(tester);

      expect(find.textContaining('Downtown Clinic'), findsOneWidget);
      expect(find.textContaining('Registering at '), findsOneWidget);
    });

    testWidgets('advanced: branch banner falls back to activeBranchNameProvider', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(),
        overrides: patientsProviderOverrides(activeBranchName: 'Clinic North'),
      );
      await pumpPatientsFrames(tester);

      expect(find.textContaining('Clinic North'), findsOneWidget);
    });

    testWidgets('advanced: edit fieldIdPrefix produces edit-patient identifiers', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(fieldIdPrefix: 'edit-patient'),
      );
      await pumpPatientsFrames(tester);

      for (final field in _fieldIds) {
        expect(find.bySemanticsIdentifier('edit-patient-$field'), findsOneWidget);
      }
      expect(find.bySemanticsIdentifier('add-patient-fullName'), findsNothing);
    });

    testWidgets('advanced: keyboard enter triggers onSubmit outside textarea', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: const _FormFieldsHarness(),
      );
      await pumpPatientsFrames(tester);

      await tester.tap(_textFieldFor('add-patient', 'fullName'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await pumpPatientsFrames(tester);

      expect(find.text('submit-count:1'), findsOneWidget);
    });
  });
}
