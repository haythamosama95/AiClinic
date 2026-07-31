import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import '../../helpers/patient_test_support.dart';
import 'detail_widget_test_harness.dart';

void main() {
  group('AppointmentBookingStep1', () {
    testWidgets('trivial: renders patient search, branch, and doctor controls', (tester) async {
      final patient = samplePatientListItem(fullName: 'Step One Patient');
      final branches = buildTestBranches();
      final doctors = buildTestDoctors();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWith(
              (ref) => FakePatientRepository(patients: [patient]),
            ),
          ],
          child: harnessMaterialApp(
            child: Scaffold(
              body: AppointmentBookingStep1(
                branchId: calendarTestBranchAId,
                branches: branches,
                branchesLoading: false,
                branchesError: false,
                doctors: doctors,
                selectedPatient: null,
                selectedDoctorId: null,
                canEdit: true,
                canChangeBranch: true,
                fallbackBranchName: 'Main',
                onPatientChanged: (_) {},
                onBranchChanged: (_) {},
                onDoctorChanged: (_) {},
                notesField: const TextField(key: Key('appointment_booking_notes')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('appointment_booking_patient_search')), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_branch')), findsOneWidget);
      expect(find.byKey(const Key('doctor_selector')), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_notes')), findsOneWidget);
    });

    testWidgets('advanced: selecting patient fires onPatientChanged', (tester) async {
      final patient = samplePatientListItem(fullName: 'Picker Patient');
      PatientListItem? selected;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWith(
              (ref) => FakePatientRepository(patients: [patient]),
            ),
          ],
          child: harnessMaterialApp(
            child: Scaffold(
              body: AppointmentBookingStep1(
                branchId: calendarTestBranchAId,
                branches: buildTestBranches(),
                branchesLoading: false,
                branchesError: false,
                doctors: buildTestDoctors(),
                selectedPatient: null,
                selectedDoctorId: null,
                canEdit: true,
                canChangeBranch: true,
                fallbackBranchName: 'Main',
                onPatientChanged: (value) => selected = value,
                onBranchChanged: (_) {},
                onDoctorChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Picker');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Picker Patient'));
      await tester.pump();

      expect(selected?.fullName, 'Picker Patient');
    });

    testWidgets('advanced: branch change fires onBranchChanged', (tester) async {
      String? changedBranch;

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep1(
              branchId: calendarTestBranchAId,
              branches: buildTestBranches(),
              branchesLoading: false,
              branchesError: false,
              doctors: buildTestDoctors(),
              selectedPatient: samplePatientListItem(),
              selectedDoctorId: null,
              canEdit: true,
              canChangeBranch: true,
              fallbackBranchName: 'Main',
              onPatientChanged: (_) {},
              onBranchChanged: (branchId) => changedBranch = branchId,
              onDoctorChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tapAppSelectOption(tester, const Key('appointment_booking_branch'), 'North');
      expect(changedBranch, calendarTestBranchBId);
    });

    testWidgets('advanced: doctor change fires onDoctorChanged', (tester) async {
      String? changedDoctor;

      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep1(
              branchId: calendarTestBranchAId,
              branches: buildTestBranches(),
              branchesLoading: false,
              branchesError: false,
              doctors: buildTestDoctors(),
              selectedPatient: samplePatientListItem(),
              selectedDoctorId: null,
              canEdit: true,
              canChangeBranch: true,
              fallbackBranchName: 'Main',
              onPatientChanged: (_) {},
              onBranchChanged: (_) {},
              onDoctorChanged: (doctorId) => changedDoctor = doctorId,
            ),
          ),
        ),
      );
      await tester.pump();

      await tapAppSelectOption(tester, const Key('doctor_selector'), 'Dr. Ada');
      expect(changedDoctor, calendarTestDoctorAId);
    });

    testWidgets('invalid state: patient and branch errors render', (tester) async {
      await tester.pumpWidget(
        harnessMaterialApp(
          child: Scaffold(
            body: AppointmentBookingStep1(
              branchId: calendarTestBranchAId,
              branches: buildTestBranches(),
              branchesLoading: false,
              branchesError: false,
              doctors: buildTestDoctors(),
              selectedPatient: null,
              selectedDoctorId: null,
              canEdit: true,
              canChangeBranch: true,
              fallbackBranchName: 'Main',
              patientError: 'Select a patient to continue.',
              branchError: 'Select a branch to continue.',
              onPatientChanged: (_) {},
              onBranchChanged: (_) {},
              onDoctorChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Select a patient to continue.'), findsOneWidget);
      expect(find.text('Select a branch to continue.'), findsOneWidget);
    });

    testWidgets('edge case: canEdit false disables patient picker', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWith((ref) => FakePatientRepository()),
          ],
          child: harnessMaterialApp(
            child: Scaffold(
              body: AppointmentBookingStep1(
                branchId: calendarTestBranchAId,
                branches: buildTestBranches(),
                branchesLoading: false,
                branchesError: false,
                doctors: buildTestDoctors(),
                selectedPatient: samplePatientListItem(),
                selectedDoctorId: null,
                canEdit: false,
                canChangeBranch: false,
                fallbackBranchName: 'Main',
                onPatientChanged: (_) {},
                onBranchChanged: (_) {},
                onDoctorChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('patient_picker_clear')), findsNothing);
    });
  });
}
