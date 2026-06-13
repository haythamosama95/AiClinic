import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapRegisterPatient(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('patient_register_submit')));
  await tester.tap(find.byKey(const Key('patient_register_submit')));
  await tester.pumpAndSettle();
}

Future<void> tapUpdatePatient(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('patient_update_submit')));
  await tester.tap(find.byKey(const Key('patient_update_submit')));
  await tester.pumpAndSettle();
}

Future<void> selectPatientGender(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AppSelect<PatientGender>, 'Gender *'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> enterPatientDateOfBirth(WidgetTester tester, {String value = '15/01/1990'}) async {
  await tester.enterText(find.widgetWithText(AppDateField, 'Date of birth *'), value);
  await tester.pumpAndSettle();
}

Future<void> fillValidCreatePatientForm(
  WidgetTester tester, {
  String name = 'New Patient',
  String phone = '201005551234',
}) async {
  await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), name);
  await tester.enterText(find.widgetWithText(AppTextField, 'Mobile number *'), phone);
  await enterPatientDateOfBirth(tester);
  await selectPatientGender(tester, 'Male');
}
