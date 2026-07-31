import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_registration_notifier.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_widget_test_harness.dart';

const _duplicateCandidate = DuplicateCandidate(
  id: '22222222-2222-4222-8222-222222222222',
  fullName: 'Existing Patient',
  branchName: 'Branch A',
  phone: '2012345678',
);

class _AddPatientDialogHost extends StatefulWidget {
  const _AddPatientDialogHost({required this.onSuccess});

  final ValueChanged<String> onSuccess;

  @override
  State<_AddPatientDialogHost> createState() => _AddPatientDialogHostState();
}

class _AddPatientDialogHostState extends State<_AddPatientDialogHost> {
  var _open = true;
  String? _successPatientId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AddPatientDialog(
          open: _open,
          onOpenChange: (open) => setState(() => _open = open),
          onSuccess: (patientId) {
            _successPatientId = patientId;
            widget.onSuccess(patientId);
          },
        ),
        Text('dialog-open:$_open'),
        Text('success-id:${_successPatientId ?? ''}'),
      ],
    );
  }
}

Finder _nameField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('add-patient-fullName'),
    matching: find.byType(TextField),
  );
}

Finder _phoneField() {
  return find.descendant(
    of: find.bySemanticsIdentifier('add-patient-phone'),
    matching: find.byType(TextField),
  );
}

Future<void> _fillValidPatientForm(WidgetTester tester) async {
  await tester.enterText(_nameField(), 'Jane Doe');
  await tester.enterText(_phoneField(), '2012345678');
  await pumpPatientsFrames(tester);
}

void main() {
  group('AddPatientDialog', () {
    testWidgets('trivial: renders when open with Cancel and Register patient actions', (tester) async {
      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
      );
      await pumpPatientsFrames(tester);

      expect(find.text('Add patient'), findsOneWidget);
      expect(find.text('Register a new patient at your active branch.'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Register patient'), findsOneWidget);
      expect(find.text('dialog-open:true'), findsOneWidget);
    });

    testWidgets('advanced: Cancel closes dialog and resets registration state', (tester) async {
      final repo = FakePatientRepository();

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await tester.enterText(_nameField(), 'Jane Doe');
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await pumpPatientsFrames(tester);

      expect(find.text('dialog-open:false'), findsOneWidget);

      final container = patientsProviderContainer(tester);
      expect(container.read(patientRegistrationProvider).values, PatientRegistrationForm.empty);
    });

    testWidgets('advanced: empty required fields show validation and skip create', (tester) async {
      final repo = FakePatientRepository();

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await tester.tap(find.widgetWithText(AppButton, 'Register patient'));
      await pumpPatientsFrames(tester);

      expect(find.text("Enter the patient's full name."), findsOneWidget);
      expect(find.text('Mobile number is required.'), findsOneWidget);
      expect(repo.createCallCount, 0);
    });

    testWidgets('advanced: successful registration creates patient and fires onSuccess', (tester) async {
      const createdId = '44444444-4444-4444-8444-444444444444';
      final repo = FakePatientRepository(
        createResult: const CreatePatientResult(patientId: createdId, mrn: 'MRN-000099'),
      );

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await _fillValidPatientForm(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Register patient'));
      await pumpPatientsFrames(tester);

      expect(repo.createCallCount, 1);
      expect(find.text('success-id:$createdId'), findsOneWidget);
      expect(find.text('dialog-open:false'), findsOneWidget);
    });

    testWidgets('advanced: submitting disables Cancel and shows loading on Register patient', (tester) async {
      final repo = FakePatientRepository(
        createDelay: const Duration(seconds: 5),
      );

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await _fillValidPatientForm(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Register patient'));
      await tester.pump();

      final cancelButton = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Cancel'));
      final registerButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Register patient'),
      );

      expect(cancelButton.disabled, isTrue);
      expect(cancelButton.onPressed, isNull);
      expect(registerButton.loading, isTrue);
      expect(registerButton.onPressed, isNull);
    });

    testWidgets('advanced: repository duplicates surface duplicate dialog', (tester) async {
      final repo = FakePatientRepository(duplicates: const [_duplicateCandidate]);

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await _fillValidPatientForm(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Register patient'));
      await pumpPatientsFrames(tester);

      expect(find.text('Possible duplicate found'), findsOneWidget);
      expect(find.byKey(ValueKey<String>(_duplicateCandidate.id)), findsOneWidget);
      expect(repo.createCallCount, 0);
    });

    testWidgets('advanced: pendingOpenPatientId closes dialog and fires onSuccess', (tester) async {
      final repo = FakePatientRepository(duplicates: const [_duplicateCandidate]);

      await pumpPatientsDialogShell(
        tester,
        home: _AddPatientDialogHost(onSuccess: (_) {}),
        overrides: patientsProviderOverrides(patientRepo: repo),
      );
      await pumpPatientsFrames(tester);

      await _fillValidPatientForm(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Register patient'));
      await pumpPatientsFrames(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey<String>(_duplicateCandidate.id)),
          matching: find.widgetWithText(AppButton, 'Open'),
        ),
      );
      await pumpPatientsFrames(tester);

      expect(find.text('success-id:${_duplicateCandidate.id}'), findsOneWidget);
      expect(find.text('dialog-open:false'), findsOneWidget);
      expect(repo.createCallCount, 0);
    });
  });
}
