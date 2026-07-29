import 'dart:async';

import 'package:clock/clock.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_confirmed_step.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step1.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/appointment_calendar_test_support.dart';
import 'detail_widget_test_harness.dart';

void main() {
  List<Override> bookingOverrides(HarnessAppointmentRepository repo) {
    return harnessDetailProviderOverrides(
      appointmentRepo: repo,
      auth: harnessAuthSession(permissions: RolePermissionSeed.receptionist),
      patientRepo: FakePatientRepository(
        patients: [samplePatientListItem(fullName: 'Booking Patient')],
      ),
    );
  }

  group('AppointmentBookingSheet', () {
    testWidgets('trivial: settings loading shows progress indicator', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.delaySettingsLoad = true;
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('invalid state: settings error shows Retry that reloads', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.getSettingsFailure = RpcFailure(
        RpcResult(success: false, errorCode: 'INTERNAL', errorMessage: 'settings failed'),
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Retry'), findsOneWidget);
      repo.getSettingsFailure = null;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.getSettingsCallCount, greaterThan(1));
      expect(find.byType(AppointmentBookingStep1), findsOneWidget);
    });

    testWidgets('trivial: step 0 renders AppointmentBookingStep1', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentBookingStep1), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_choose_time')), findsOneWidget);
    });

    testWidgets('advanced: Choose time advances to step 2', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Booking');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Booking Patient'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentBookingStep2), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_submit')), findsOneWidget);
    });

    testWidgets('invalid state: step 1 validation messages for patient and branch', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          branchId: '',
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();

      expect(find.text('Select a patient to continue.'), findsOneWidget);
      expect(find.text('Select a branch to continue.'), findsOneWidget);
    });

    testWidgets('advanced: successful submit shows confirmed step and Done button', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Booking');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Booking Patient'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentBookingConfirmedStep), findsOneWidget);
      expect(find.text('Appointment booked'), findsOneWidget);
      expect(find.byKey(const Key('appointment_booking_done')), findsOneWidget);
      expect(repo.createCallCount, 1);
    });

    testWidgets('invalid state: SCHEDULE_CONFLICT shows conflict alert', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.createFailure = RpcFailure(
        RpcResult(success: false, errorCode: 'SCHEDULE_CONFLICT', errorMessage: 'overlap'),
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(const Key('appointment_booking_patient_search')), 'Booking');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Booking Patient'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(appointmentMessageForRpc(repo.createFailure!)),
        findsOneWidget,
      );
    });

    testWidgets('advanced: edit mode prefills and calls update path', (tester) async {
      final repo = HarnessAppointmentRepository();
      final existing = buildAppointmentDetail(
        patientName: 'Existing Patient',
        status: AppointmentStatus.confirmed,
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          existingAppointment: existing,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Existing Patient'), findsWidgets);
      expect(find.text('Save changes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.updateCallCount, 1);
      expect(find.byType(AppointmentBookingConfirmedStep), findsOneWidget);
    });

    testWidgets('advanced: Cancel button closes dialog before confirmation', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AppointmentBookingStep1), findsNothing);
    });

    testWidgets('invalid state: end time must be after start time', (tester) async {
      final repo = HarnessAppointmentRepository();
      final start = DateTime(2026, 6, 15, 10, 0);
      final existing = buildAppointmentDetail(
        status: AppointmentStatus.confirmed,
        startTime: start,
        durationMinutes: 0,
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          existingAppointment: existing,
          slotStart: start,
          slotEnd: start,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();

      expect(find.text('End time must be after start time.'), findsOneWidget);
    });

    testWidgets('invalid state: duration below settings minimum', (tester) async {
      final repo = HarnessAppointmentRepository();
      repo.settings = AppointmentSettings(
        defaultDurationMinutes: 3,
        minDurationMinutes: 5,
        maxDurationMinutes: 240,
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await selectPatientAndAdvanceToStep2(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();

      expect(find.text('Duration must be at least 5 minutes.'), findsOneWidget);
    });

    testWidgets('invalid state: start time must be in the future', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await selectPatientAndAdvanceToStep2(tester);
      await tester.tap(find.text('9:00 AM'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();

      expect(find.text('Start time must be in the future.'), findsOneWidget);
    });

    testWidgets('invalid state: notes over 2000 characters rejected', (tester) async {
      final repo = HarnessAppointmentRepository();
      final existing = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          existingAppointment: existing,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await enterBookingNotes(tester, 'x' * 2001);
      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();

      expect(find.text('Notes must be 2000 characters or fewer.'), findsOneWidget);
    });

    testWidgets('edge case: notes at 2000 characters accepted on save', (tester) async {
      final repo = HarnessAppointmentRepository();
      final existing = buildAppointmentDetail(status: AppointmentStatus.confirmed);
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          existingAppointment: existing,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await enterBookingNotes(tester, 'n' * 2000);
      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Notes must be 2000 characters or fewer.'), findsNothing);
      expect(find.byType(AppointmentBookingConfirmedStep), findsOneWidget);
      expect(repo.updateCallCount, 1);
    });

    testWidgets('invalid state: appointment outside branch working hours', (tester) async {
      final repo = HarnessAppointmentRepository();
      final schedule = buildHarnessUniformSchedule(openTime: '09:00', closeTime: '10:35');
      repo.settings = AppointmentSettings(
        defaultDurationMinutes: 30,
        minDurationMinutes: 5,
        maxDurationMinutes: 240,
        workingSchedule: schedule,
      );
      final start = DateTime(2026, 6, 15, 10, 0);
      final slotEnd = DateTime(2026, 6, 15, 10, 45);
      final existing = buildAppointmentDetail(
        status: AppointmentStatus.confirmed,
        startTime: start,
        durationMinutes: 30,
      );
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(
          tester,
          overrides: bookingOverrides(repo),
          appointmentRepo: repo,
          existingAppointment: existing,
          slotStart: start,
          slotEnd: slotEnd,
          schedule: schedule,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const Key('appointment_booking_choose_time')));
      await tester.pump();

      expect(
        find.text('Appointment must be within branch working hours.'),
        findsOneWidget,
      );
    });

    testWidgets('invalid state: selected slot no longer available on submit', (tester) async {
      final repo = HarnessAppointmentRepository();
      final slotTime = DateTime(2026, 6, 15, 11, 0);
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await selectPatientAndAdvanceToStep2(tester);
      await tester.tap(find.text('11:00 AM'));
      await tester.pump();

      repo.listAppointmentsResult = [
        buildAppointmentListItem(
          startTime: slotTime,
          doctorId: calendarTestDoctorAId,
          status: AppointmentStatus.confirmed,
        ),
      ];
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();

      expect(find.text('This slot is no longer available.'), findsOneWidget);
    });

    testWidgets('advanced: backdrop dismisses dialog when idle', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentBookingStep1), findsOneWidget);
      await tapBookingDialogBackdrop(tester);

      expect(find.byType(AppointmentBookingStep1), findsNothing);
    });

    testWidgets('invalid state: backdrop does not dismiss while saving', (tester) async {
      final repo = HarnessAppointmentRepository();
      final completer = Completer<CreateAppointmentResult>();
      repo.createAppointmentCompleter = completer;
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await selectPatientAndAdvanceToStep2(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();

      expect(find.byType(AppointmentBookingStep2), findsOneWidget);
      await tapBookingDialogBackdrop(tester);
      expect(find.byType(AppointmentBookingStep2), findsOneWidget);

      completer.complete(
        CreateAppointmentResult(
          appointmentId: 'new-appointment-id',
          startTime: detailHarnessFixedNow,
          endTime: detailHarnessFixedNow.add(const Duration(minutes: 30)),
          status: AppointmentStatus.scheduled,
          type: AppointmentType.planned,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('invalid state: backdrop does not dismiss after confirmation', (tester) async {
      final repo = HarnessAppointmentRepository();
      await withClock(Clock.fixed(detailHarnessFixedNow), () async {
        await pumpBookingSheetHost(tester, overrides: bookingOverrides(repo), appointmentRepo: repo);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await selectPatientAndAdvanceToStep2(tester);
      await tester.tap(find.byKey(const Key('appointment_booking_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AppointmentBookingConfirmedStep), findsOneWidget);
      await tapBookingDialogBackdrop(tester);
      expect(find.byType(AppointmentBookingConfirmedStep), findsOneWidget);
    });
  });
}
