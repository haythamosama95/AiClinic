import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentRescheduleConfirmDialog', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();
    final thursday = DateTime(2026, 6, 4, 10, 0);
    final thursdayEnd = DateTime(2026, 6, 4, 10, 30);

    AppointmentListItem sampleAppointment() {
      return AppointmentListItem(
        id: 'a1',
        patientId: 'p1',
        patientName: 'Jane Doe',
        doctorId: 'd1',
        doctorName: 'Dr Ada',
        startTime: thursday,
        endTime: thursdayEnd,
        type: AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );
    }

    Future<void> openDialog(WidgetTester tester, {DateTime? newStart, DateTime? newEnd}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: AppButton(
                  label: 'Open dialog',
                  onPressed: () {
                    AppointmentRescheduleConfirmDialog.show(
                      context,
                      appointment: sampleAppointment(),
                      newStart: newStart ?? DateTime(2026, 6, 4, 11, 0),
                      newEnd: newEnd ?? DateTime(2026, 6, 4, 11, 30),
                      schedule: schedule,
                      branchAppointments: [sampleAppointment()],
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    group('CAL-G — confirm dialog', () {
      testWidgets('CAL-G04: cancel dialog closes without confirming move', (tester) async {
        await openDialog(tester);

        expect(find.text('Move appointment?'), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Move appointment?'), findsNothing);
      });

      testWidgets('CAL-G14: editing start into overlap disables Move and shows validation error', (tester) async {
        final blocker = AppointmentListItem(
          id: 'a2',
          patientId: 'p2',
          patientName: 'Blocked',
          doctorId: 'd1',
          doctorName: 'Dr Ada',
          startTime: DateTime(2026, 6, 4, 11, 0),
          endTime: DateTime(2026, 6, 4, 11, 30),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child!),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: AppButton(
                    label: 'Open dialog',
                    onPressed: () {
                      AppointmentRescheduleConfirmDialog.show(
                        context,
                        appointment: sampleAppointment(),
                        newStart: DateTime(2026, 6, 4, 11, 0),
                        newEnd: DateTime(2026, 6, 4, 11, 30),
                        schedule: schedule,
                        branchAppointments: [sampleAppointment(), blocker],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Open dialog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('overlaps'), findsOneWidget);

        final moveButton = tester.widget<AppButton>(find.byKey(const Key('appointment_reschedule_confirm')));
        expect(moveButton.onPressed, isNull);
      });
    });
  });
}
