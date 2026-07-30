import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_dialog.dart';

import 'visit_widget_test_harness.dart';

const _patientName = 'Jane Doe';

PatientDetail _testPatient() {
  return PatientDetail(
    id: encounterTestPatientId,
    fullName: _patientName,
    dateOfBirth: DateTime.utc(1990, 1, 15),
    branchId: encounterTestBranchId,
    branchName: 'Main Branch',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

AppointmentDetail _testAppointment() {
  return AppointmentDetail(
    id: encounterTestAppointmentId,
    branchId: encounterTestBranchId,
    patientId: encounterTestPatientId,
    patientName: _patientName,
    doctorId: encounterTestDoctorId,
    doctorName: 'Dr Test',
    startTime: DateTime.utc(2026, 5, 31, 9),
    endTime: DateTime.utc(2026, 5, 31, 9, 30),
    type: AppointmentType.planned,
    status: AppointmentStatus.completed,
    createdAt: DateTime.utc(2026, 5, 31),
    updatedAt: DateTime.utc(2026, 5, 31),
  );
}

List<Override> _submittedDialogOverrides({
  Future<PatientDetail> Function(Ref ref)? patient,
  Future<AppointmentDetail> Function(Ref ref)? appointment,
  Future<List<BranchSummary>> Function(Ref ref)? branches,
  List<Override> extraOverrides = const [],
}) {
  final visit = sampleEncounterVisit();
  return visitsProviderOverrides(
    auth: visitsAuthSession(),
    extraOverrides: [
      patientDetailProvider(visit.patientId).overrideWith(
        patient ?? ((ref) async => _testPatient()),
      ),
      appointmentDetailProvider(visit.appointmentId).overrideWith(
        appointment ?? ((ref) async => _testAppointment()),
      ),
      staffAssignableBranchesProvider.overrideWith(
        branches ?? ((ref) async => [BranchSummary(id: encounterTestBranchId, name: 'Main Branch')]),
      ),
      ...extraOverrides,
    ],
  );
}

class _DialogLauncher extends ConsumerStatefulWidget {
  const _DialogLauncher({this.kind = VisitConfirmationKind.completed});

  final VisitConfirmationKind kind;

  @override
  ConsumerState<_DialogLauncher> createState() => _DialogLauncherState();
}

class _DialogLauncherState extends ConsumerState<_DialogLauncher> {
  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => VisitSubmittedDialog.show(
        context,
        ref,
        visit: sampleEncounterVisit(),
        kind: widget.kind,
        actionAt: DateTime.utc(2026, 5, 31, 10, 15),
      ),
      child: const Text('open-dialog'),
    );
  }
}

Future<void> _openSubmittedDialog(
  WidgetTester tester, {
  List<Override> overrides = const [],
  VisitConfirmationKind kind = VisitConfirmationKind.completed,
}) async {
  await pumpVisitsRouter(
    tester,
    home: _DialogLauncher(kind: kind),
    overrides: overrides,
  );
  await tester.tap(find.text('open-dialog'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapVisibleButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(AppButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
}

void main() {
  group('VisitSubmittedDialog.show', () {
    testWidgets('trivial: displays confirmation content and footer actions', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(),
      );

      expect(find.byType(VisitSubmittedCombinedConfirmation), findsOneWidget);
      expect(find.text('View appointment'), findsOneWidget);
      expect(find.text('Back to calendar'), findsOneWidget);
      expect(find.text('Visit completed'), findsOneWidget);
      expect(find.textContaining(_patientName), findsWidgets);
    });

    testWidgets('advanced: View appointment navigates to appointment stub route', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(),
      );

      await _tapVisibleButton(tester, 'View appointment');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('stub:appointment-$encounterTestAppointmentId'), findsOneWidget);
      expect(find.byType(VisitSubmittedCombinedConfirmation), findsNothing);
    });

    testWidgets('advanced: Back to calendar navigates to calendar stub route', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(),
      );

      await _tapVisibleButton(tester, 'Back to calendar');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('stub:appointments-calendar'), findsOneWidget);
      expect(find.byType(VisitSubmittedCombinedConfirmation), findsNothing);
    });

    testWidgets('edge case: barrier tap dismisses dialog', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(),
      );

      expect(find.byType(VisitSubmittedCombinedConfirmation), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(VisitSubmittedCombinedConfirmation), findsNothing);
    });
  });

  group('VisitSubmittedDialog — provider states', () {
    testWidgets('invalid state: appointment loading shows skeleton', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          appointment: (ref) => Completer<AppointmentDetail>().future,
        ),
      );

      expect(find.byType(AppSkeleton), findsOneWidget);
      expect(find.byType(VisitSubmittedCombinedConfirmation), findsNothing);
    });

    testWidgets('invalid state: appointment error still renders confirmation with visit fallback slot', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          appointment: (ref) async => throw visitsRpcFailure(message: 'Appointment unavailable.'),
        ),
      );

      expect(find.byType(VisitSubmittedCombinedConfirmation), findsOneWidget);
      expect(find.text('Visit details'), findsOneWidget);
      expect(find.text('Appointment'), findsOneWidget);
    });

    testWidgets('invalid state: patient loading uses Patient fallback name', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          patient: (ref) => Completer<PatientDetail>().future,
        ),
      );

      expect(find.textContaining('Patient'), findsWidgets);
      expect(find.textContaining(_patientName), findsNothing);
    });

    testWidgets('invalid state: patient error uses Patient fallback name', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          patient: (ref) async => throw visitsRpcFailure(message: 'Patient unavailable.'),
        ),
      );

      expect(find.textContaining('Patient'), findsWidgets);
      expect(find.textContaining(_patientName), findsNothing);
    });

    testWidgets('invalid state: branches loading uses Branch fallback name', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          branches: (ref) => Completer<List<BranchSummary>>().future,
        ),
      );

      expect(find.text('Branch'), findsWidgets);
      expect(find.text('Main Branch'), findsNothing);
    });

    testWidgets('invalid state: branches error uses Branch fallback name', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          branches: (ref) async => throw StateError('Branches unavailable.'),
        ),
      );

      expect(find.text('Branch'), findsWidgets);
      expect(find.text('Main Branch'), findsNothing);
    });

    testWidgets('edge case: branches loaded without matching visit branch falls back to Branch', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(
          branches: (ref) async => [const BranchSummary(id: 'other-branch', name: 'Other Branch')],
        ),
      );

      expect(find.text('Branch'), findsWidgets);
      expect(find.text('Other Branch'), findsNothing);
    });

    testWidgets('advanced: edited kind uses Changes saved title', (tester) async {
      await _openSubmittedDialog(
        tester,
        overrides: _submittedDialogOverrides(),
        kind: VisitConfirmationKind.edited,
      );

      expect(find.text('Changes saved'), findsOneWidget);
      expect(find.textContaining('Documentation for'), findsOneWidget);
    });
  });
}
