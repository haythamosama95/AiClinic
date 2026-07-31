import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';

import 'calendar_widget_test_harness.dart';

void main() {
  final schedule = BranchWorkingSchedule.defaultSchedule();
  final thursday = DateTime(2026, 6, 4, 10, 0);
  final thursdayEnd = DateTime(2026, 6, 4, 10, 30);

  Future<PendingDialogResult<AppointmentRescheduleConfirmResult?>> openDialog(
    WidgetTester tester, {
    required AppointmentListItem appointment,
    required DateTime newStart,
    required DateTime newEnd,
    List<AppointmentListItem> branchAppointments = const [],
  }) async {
    late Future<AppointmentRescheduleConfirmResult?> result;
    await pumpDialogShell(
      tester,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            result = AppointmentRescheduleConfirmDialog.show(
              context,
              appointment: appointment,
              newStart: newStart,
              newEnd: newEnd,
              schedule: schedule,
              branchAppointments: branchAppointments.isEmpty ? [appointment] : branchAppointments,
            );
          },
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return PendingDialogResult(result);
  }

  testWidgets('trivial: CAL-RESCHED-01 pickers and confirm key are present', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
      );

      expect(find.byKey(const Key('appointment_reschedule_pick_date')), findsOneWidget);
      expect(find.byKey(const Key('appointment_reschedule_pick_start')), findsOneWidget);
      expect(find.byKey(const Key('appointment_reschedule_pick_end')), findsOneWidget);
      expect(find.byKey(const Key('appointment_reschedule_confirm')), findsOneWidget);
    });
  });

  testWidgets('invalid state: CAL-RESCHED-02 end before start shows validation message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 10, 30),
      );

      expect(find.text('End time must be after start time.'), findsOneWidget);
      final moveButton = tester.widget<AppButton>(find.byKey(const Key('appointment_reschedule_confirm')));
      expect(moveButton.disabled, isTrue);
    });
  });

  testWidgets('invalid state: CAL-RESCHED-03 confirmed appointment shows status message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd, status: AppointmentStatus.confirmed),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
      );

      expect(
        find.text('Only scheduled appointments can be moved. Confirmed appointments must be cancelled and re-booked.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('invalid state: CAL-RESCHED-04 short duration shows reschedule message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursday.add(const Duration(minutes: 4))),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
      );

      expect(find.text('Appointment duration is too short to reschedule.'), findsOneWidget);
    });
  });

  testWidgets('invalid state: CAL-RESCHED-05 outside working hours shows branch hours message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd),
        newStart: DateTime(2026, 6, 4, 6, 0),
        newEnd: DateTime(2026, 6, 4, 6, 30),
      );

      expect(find.textContaining('Appointment must be within branch working hours'), findsOneWidget);
    });
  });

  testWidgets('invalid state: CAL-RESCHED-06 overlap shows overlap message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      final appointment = calendarAppointmentItem(
        id: 'a1',
        patientId: 'p1',
        patientName: 'Patient A',
        start: thursday,
        end: thursdayEnd,
      );
      final blocker = calendarAppointmentItem(
        id: 'a2',
        patientId: 'p2',
        patientName: 'Patient B',
        start: DateTime(2026, 6, 4, 10, 15),
        end: DateTime(2026, 6, 4, 10, 45),
      );

      await openDialog(
        tester,
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 10, 0),
        newEnd: DateTime(2026, 6, 4, 10, 30),
        branchAppointments: [appointment, blocker],
      );

      expect(find.text('The doctor is not available at this time (overlaps with Patient B).'), findsOneWidget);
    });
  });

  testWidgets('invalid state: CAL-RESCHED-07 patient same-day shows duplicate-day message', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      final appointment = calendarAppointmentItem(
        id: 'a1',
        patientId: 'p1',
        patientName: 'Patient A',
        start: thursday,
        end: thursdayEnd,
      );
      final sameDay = calendarAppointmentItem(
        id: 'a2',
        patientId: 'p1',
        patientName: 'Patient A',
        start: DateTime(2026, 6, 4, 14, 0),
        end: DateTime(2026, 6, 4, 14, 30),
      );

      await openDialog(
        tester,
        appointment: appointment,
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
        branchAppointments: [appointment, sameDay],
      );

      expect(find.text('This patient already has an appointment on the same day.'), findsOneWidget);
    });
  });

  testWidgets('advanced: CAL-RESCHED-08 Cancel pops without a result', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      final dialog = await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(await dialog.result, isNull);
    });
  });

  testWidgets('advanced: CAL-RESCHED-09 Move pops AppointmentRescheduleConfirmResult on valid move', (tester) async {
    await withClock(Clock.fixed(DateTime(2026, 6, 1)), () async {
      final dialog = await openDialog(
        tester,
        appointment: calendarAppointmentItem(start: thursday, end: thursdayEnd),
        newStart: DateTime(2026, 6, 4, 11, 0),
        newEnd: DateTime(2026, 6, 4, 11, 30),
      );

      await tester.tap(find.byKey(const Key('appointment_reschedule_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final result = await dialog.result;
      expect(result, isA<AppointmentRescheduleConfirmResult>());
      expect(result!.start, DateTime(2026, 6, 4, 11, 0));
      expect(result.end, DateTime(2026, 6, 4, 11, 30));
    });
  });

  test('trivial: CAL-RESCHED-10 doctor-move validation string matches domain', () {
    final appointment = calendarAppointmentItem();
    final message = AppointmentRescheduleValidation.validateDoctorResourceMove(
      appointment: appointment,
      targetDoctorId: 'other-doctor-id',
    );
    expect(
      message,
      'Moving an appointment to another doctor is not supported. Cancel and re-book to change the doctor.',
    );
  });
}
