import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
<<<<<<< HEAD
import 'package:fake_async/fake_async.dart';
=======
import 'package:clock/clock.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentBookingSlots', () {
    final schedule = BranchWorkingSchedule.defaultSchedule();
    final doctors = [
      const StaffListItem(
        id: 'doc-1',
        fullName: 'Dr. Ada',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: 'branch-1', name: 'Main')],
      ),
      const StaffListItem(
        id: 'doc-2',
        fullName: 'Dr. Ben',
        role: StaffRole.doctor,
        isActive: true,
        branches: [StaffBranchLabel(id: 'branch-1', name: 'Main')],
      ),
    ];

    AppointmentListItem appointment({
      required String id,
      required DateTime start,
      String doctorId = 'doc-1',
      AppointmentStatus status = AppointmentStatus.scheduled,
    }) {
      return AppointmentListItem(
        id: id,
        patientId: 'patient-$id',
        patientName: 'Patient $id',
        doctorId: doctorId,
        doctorName: 'Doctor',
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('trivial: dayOptions generates consecutive calendar days from anchor', () {
      final anchor = DateTime(2026, 7, 13, 15, 45);
      final days = AppointmentBookingSlots.dayOptions(anchor: anchor, count: 3);

      expect(days, [
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 14),
        DateTime(2026, 7, 15),
      ]);
    });

    test('trivial: isSelectableDay mirrors branch working-day rules', () {
      expect(AppointmentBookingSlots.isSelectableDay(schedule, DateTime(2026, 7, 13)), isTrue);
      expect(AppointmentBookingSlots.isSelectableDay(schedule, DateTime(2026, 7, 12)), isFalse);
    });

    test('edge case: slotsForDay returns empty on non-working day', () {
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 12),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      );

      expect(slots, isEmpty);
    });

    test('invalid state: slotsForDay returns empty when hours are unparseable', () {
      final badHours = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day == BranchWeekday.monday,
                openTime: day == BranchWeekday.monday ? '9:00' : null,
                closeTime: day == BranchWeekday.monday ? '17:00' : null,
              ),
            )
            .toList(growable: false),
      );
      final monday = DateTime(2026, 7, 13);

      expect(AppointmentBookingSlots.slotsForDay(
        schedule: badHours,
        date: monday,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      ), isEmpty);
    });

    test('invalid state: slotsForDay returns empty when open is not before close', () {
      final inverted = BranchWorkingSchedule(
        BranchWeekday.values
            .map(
              (day) => BranchWorkingDayHours(
                day: day,
                isWorkingDay: day == BranchWeekday.monday,
                openTime: day == BranchWeekday.monday ? '17:00' : null,
                closeTime: day == BranchWeekday.monday ? '09:00' : null,
              ),
            )
            .toList(growable: false),
      );

      expect(AppointmentBookingSlots.slotsForDay(
        schedule: inverted,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      ), isEmpty);
    });

    test('marks slot preferred when preferred doctor is free', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
        preferredDoctorId: 'doc-1',
      );

      expect(slots, isNotEmpty);
      expect(slots.first.status, AppointmentBookingSlotStatus.preferred);
    });

    test('marks slot available when no preferred doctor is set', () {
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      );

      expect(slots.first.status, AppointmentBookingSlotStatus.available);
    });

    test('marks slot alternate when only other doctors are free', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final occupiedStart = DateTime(2026, 7, 13, 9, 0);
      final appointments = [
        appointment(id: 'appt-1', start: occupiedStart, doctorId: 'doc-1'),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
        preferredDoctorId: 'doc-1',
      );

      final nineAm = slots.firstWhere((slot) => slot.start.hour == 9 && slot.start.minute == 0);
      expect(nineAm.status, AppointmentBookingSlotStatus.alternate);
      expect(nineAm.availableDoctorIds, contains('doc-2'));
    });

    test('marks slot locked when all doctors are booked', () {
      final day = DateTime(2026, 7, 13, 0, 0);
      final occupiedStart = DateTime(2026, 7, 13, 9, 0);
      final appointments = [
        appointment(id: 'appt-1', start: occupiedStart, doctorId: 'doc-1'),
        appointment(id: 'appt-2', start: occupiedStart, doctorId: 'doc-2'),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: day,
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
        preferredDoctorId: 'doc-1',
      );

      final nineAm = slots.firstWhere((slot) => slot.start.hour == 9 && slot.start.minute == 0);
      expect(nineAm.status, AppointmentBookingSlotStatus.locked);
    });

    test('edge case: first slot starts exactly at branch open', () {
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      );

      expect(slots.first.start, DateTime(2026, 7, 13, 9, 0));
    });

    test('edge case: last slot ends exactly at branch close', () {
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: const [],
      );

      final last = slots.last;
      expect(last.start, DateTime(2026, 7, 13, 16, 30));
      expect(last.start.add(const Duration(minutes: 30)), DateTime(2026, 7, 13, 17, 0));
    });

    test('edge case: zero doctors yields all locked slots', () {
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: const [],
        existingAppointments: const [],
      );

      expect(slots, isNotEmpty);
      expect(slots.every((slot) => slot.status == AppointmentBookingSlotStatus.locked), isTrue);
    });

    test('edge case: inactive doctors are ignored for availability', () {
      final inactiveOnly = [
        const StaffListItem(
          id: 'doc-off',
          fullName: 'Dr. Off',
          role: StaffRole.doctor,
          isActive: false,
        ),
      ];
      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: inactiveOnly,
        existingAppointments: const [],
      );

      expect(slots.every((slot) => slot.status == AppointmentBookingSlotStatus.locked), isTrue);
    });

    test('regression: cancelled and no-show appointments do not block scheduling', () {
      final blockedStart = DateTime(2026, 7, 13, 10, 0);
      final appointments = [
        appointment(id: 'cancelled', start: blockedStart, status: AppointmentStatus.cancelled),
        appointment(id: 'no-show', start: blockedStart, doctorId: 'doc-2', status: AppointmentStatus.noShow),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
      );

      final tenAm = slots.firstWhere((slot) => slot.start.hour == 10 && slot.start.minute == 0);
      expect(tenAm.status, isNot(AppointmentBookingSlotStatus.locked));
      expect(tenAm.availableDoctorIds, containsAll(['doc-1', 'doc-2']));
    });

    test('advanced: overlapping existing appointment blocks only assigned doctor', () {
      final overlapStart = DateTime(2026, 7, 13, 11, 0);
      final appointments = [
        AppointmentListItem(
          id: 'long',
          patientId: 'p1',
          patientName: 'Patient',
          doctorId: 'doc-1',
          doctorName: 'Dr. Ada',
          startTime: overlapStart,
          endTime: overlapStart.add(const Duration(minutes: 60)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
        preferredDoctorId: 'doc-1',
      );

      final elevenThirty = slots.firstWhere((slot) => slot.start.hour == 11 && slot.start.minute == 30);
      expect(elevenThirty.status, AppointmentBookingSlotStatus.alternate);
      expect(elevenThirty.availableDoctorIds, ['doc-2']);
    });

    test('advanced: doctor busy for entire day locks every slot', () {
      final dayStart = DateTime(2026, 7, 13, 9, 0);
      final appointments = [
        AppointmentListItem(
          id: 'all-day',
          patientId: 'p1',
          patientName: 'Patient',
          doctorId: 'doc-1',
          doctorName: 'Dr. Ada',
          startTime: dayStart,
          endTime: dayStart.add(const Duration(hours: 8)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
        AppointmentListItem(
          id: 'all-day-2',
          patientId: 'p2',
          patientName: 'Patient 2',
          doctorId: 'doc-2',
          doctorName: 'Dr. Ben',
          startTime: dayStart,
          endTime: dayStart.add(const Duration(hours: 8)),
          type: AppointmentType.planned,
          status: AppointmentStatus.scheduled,
        ),
      ];

      final slots = AppointmentBookingSlots.slotsForDay(
        schedule: schedule,
        date: DateTime(2026, 7, 13),
        slotMinutes: 30,
        durationMinutes: 30,
        branchDoctors: doctors,
        existingAppointments: appointments,
      );

      expect(slots.every((slot) => slot.status == AppointmentBookingSlotStatus.locked), isTrue);
    });

    group('resolveAssignedDoctorId', () {
<<<<<<< HEAD
      const preferredSlot = AppointmentBookingTimeSlot(
        start: DateTime(2026, 7, 13, 9),
        label: '9:00 AM',
        status: AppointmentBookingSlotStatus.preferred,
        availableDoctorIds: ['doc-1', 'doc-2'],
      );

      test('returns null for locked slots', () {
        const locked = AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9),
          label: '9:00 AM',
          status: AppointmentBookingSlotStatus.locked,
          availableDoctorIds: [],
=======
      final preferredSlot = AppointmentBookingTimeSlot(
        start: DateTime(2026, 7, 13, 9),
        label: '9:00 AM',
        status: AppointmentBookingSlotStatus.preferred,
        availableDoctorIds: const ['doc-1', 'doc-2'],
      );

      test('returns null for locked slots', () {
        final locked = AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9),
          label: '9:00 AM',
          status: AppointmentBookingSlotStatus.locked,
          availableDoctorIds: const [],
>>>>>>> master
        );

        expect(
          AppointmentBookingSlots.resolveAssignedDoctorId(slot: locked, preferredDoctorId: 'doc-1'),
          isNull,
        );
      });

      test('returns null when no doctors are available', () {
<<<<<<< HEAD
        const emptyDoctors = AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9),
          label: '9:00 AM',
          status: AppointmentBookingSlotStatus.available,
          availableDoctorIds: [],
=======
        final emptyDoctors = AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9),
          label: '9:00 AM',
          status: AppointmentBookingSlotStatus.available,
          availableDoctorIds: const [],
>>>>>>> master
        );

        expect(AppointmentBookingSlots.resolveAssignedDoctorId(slot: emptyDoctors), isNull);
      });

      test('returns preferred doctor when present in availability', () {
        expect(
          AppointmentBookingSlots.resolveAssignedDoctorId(slot: preferredSlot, preferredDoctorId: 'doc-2'),
          'doc-2',
        );
      });

      test('returns first available doctor when preferred is absent', () {
        expect(
          AppointmentBookingSlots.resolveAssignedDoctorId(slot: preferredSlot, preferredDoctorId: 'doc-missing'),
          'doc-1',
        );
      });
    });

    test('trivial: openSlotCount excludes locked slots', () {
<<<<<<< HEAD
      const slots = [
=======
      final slots = [
>>>>>>> master
        AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9),
          label: '9:00 AM',
          status: AppointmentBookingSlotStatus.locked,
<<<<<<< HEAD
          availableDoctorIds: [],
=======
          availableDoctorIds: const [],
>>>>>>> master
        ),
        AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 9, 30),
          label: '9:30 AM',
          status: AppointmentBookingSlotStatus.available,
<<<<<<< HEAD
          availableDoctorIds: ['doc-1'],
=======
          availableDoctorIds: const ['doc-1'],
>>>>>>> master
        ),
        AppointmentBookingTimeSlot(
          start: DateTime(2026, 7, 13, 10),
          label: '10:00 AM',
          status: AppointmentBookingSlotStatus.preferred,
<<<<<<< HEAD
          availableDoctorIds: ['doc-1'],
=======
          availableDoctorIds: const ['doc-1'],
>>>>>>> master
        ),
      ];

      expect(AppointmentBookingSlots.openSlotCount(slots), 2);
    });

    test('trivial: dayFetchRange covers a single local calendar day', () {
      final day = DateTime(2026, 7, 13, 11, 30);
      final range = AppointmentBookingSlots.dayFetchRange(day);

      expect(range.from, DateTime(2026, 7, 13));
      expect(range.to, DateTime(2026, 7, 14));
    });

    test('edge case: multiDayFetchRange empty defaults to today', () {
<<<<<<< HEAD
      FakeAsync().run((async) {
        final anchor = DateTime(2026, 7, 15, 14, 30);
        async.elapse(anchor.difference(DateTime(1970, 1, 1)));

=======
      final anchor = DateTime(2026, 7, 15, 14, 30);
      withClock(Clock.fixed(anchor), () {
>>>>>>> master
        final range = AppointmentBookingSlots.multiDayFetchRange([]);

        expect(range.from, DateTime(anchor.year, anchor.month, anchor.day));
        expect(range.to, range.from.add(const Duration(days: 1)));
      });
    });

    test('advanced: multiDayFetchRange spans sorted first through last day', () {
      final range = AppointmentBookingSlots.multiDayFetchRange([
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 15),
        DateTime(2026, 7, 18),
      ]);

      expect(range.from, DateTime(2026, 7, 15));
      expect(range.to, DateTime(2026, 7, 21));
    });

    test('advanced: defaultSlotMinutes accepts supported settings values', () {
      for (final minutes in AppointmentCalendarDisplay.supportedTimeIntervalMinutes) {
        expect(AppointmentBookingSlots.defaultSlotMinutes(minutes), minutes);
      }
    });

    test('invalid state: defaultSlotMinutes falls back for unsupported interval', () {
      expect(
        AppointmentBookingSlots.defaultSlotMinutes(20),
        AppointmentCalendarDisplay.defaultTimeIntervalMinutes,
      );
      expect(
        AppointmentBookingSlots.defaultSlotMinutes(null),
        AppointmentCalendarDisplay.defaultTimeIntervalMinutes,
      );
    });
  });
}
