import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';

/// Availability state for a bookable time slot (web `SlotStatus`).
enum AppointmentBookingSlotStatus { locked, available, preferred, alternate }

/// A single selectable booking slot on step 2.
@immutable
class AppointmentBookingTimeSlot {
  const AppointmentBookingTimeSlot({
    required this.start,
    required this.label,
    required this.status,
    required this.availableDoctorIds,
  });

  final DateTime start;
  final String label;
  final AppointmentBookingSlotStatus status;
  final List<String> availableDoctorIds;
}

/// Pure rules for day options and per-day slot availability in the booking dialog.
class AppointmentBookingSlots {
  AppointmentBookingSlots._();

  static const int defaultDayCount = 14;

  static List<DateTime> dayOptions({
    required DateTime anchor,
    int count = defaultDayCount,
  }) {
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    return List.generate(count, (index) => today.add(Duration(days: index)));
  }

  static bool isSelectableDay(BranchWorkingSchedule schedule, DateTime date) {
    return AppointmentBranchWorkingHours.isWorkingDay(schedule, date);
  }

  static List<AppointmentBookingTimeSlot> slotsForDay({
    required BranchWorkingSchedule schedule,
    required DateTime date,
    required int slotMinutes,
    required int durationMinutes,
    required List<StaffListItem> branchDoctors,
    required List<AppointmentListItem> existingAppointments,
    String? preferredDoctorId,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    if (!isSelectableDay(schedule, day)) {
      return const [];
    }

    final dayHours = AppointmentBranchWorkingHours.hoursForDate(schedule, day);
    if (dayHours == null || !dayHours.isWorkingDay) {
      return const [];
    }

    final openMinutes = AppointmentBranchWorkingHours.parseHm(
      dayHours.openTime,
    );
    final closeMinutes = AppointmentBranchWorkingHours.parseHm(
      dayHours.closeTime,
    );
    if (openMinutes == null ||
        closeMinutes == null ||
        openMinutes >= closeMinutes) {
      return const [];
    }

    final doctors = branchDoctors
        .where((doctor) => doctor.isActive)
        .toList(growable: false);
    final slots = <AppointmentBookingTimeSlot>[];
    final timeLabel = DateFormat.jm();

    for (
      var startMinutes = openMinutes;
      startMinutes + durationMinutes <= closeMinutes;
      startMinutes += slotMinutes
    ) {
      final start = DateTime(
        day.year,
        day.month,
        day.day,
        startMinutes ~/ 60,
        startMinutes % 60,
      );
      final end = start.add(Duration(minutes: durationMinutes));
      final availableDoctorIds = <String>[];

      for (final doctor in doctors) {
        if (_isDoctorFree(
          doctorId: doctor.id,
          start: start,
          end: end,
          appointments: existingAppointments,
        )) {
          availableDoctorIds.add(doctor.id);
        }
      }

      final status = _resolveStatus(availableDoctorIds, preferredDoctorId);
      slots.add(
        AppointmentBookingTimeSlot(
          start: start,
          label: timeLabel.format(start),
          status: status,
          availableDoctorIds: availableDoctorIds,
        ),
      );
    }

    return slots;
  }

  static String? resolveAssignedDoctorId({
    required AppointmentBookingTimeSlot slot,
    String? preferredDoctorId,
  }) {
    if (slot.status == AppointmentBookingSlotStatus.locked ||
        slot.availableDoctorIds.isEmpty) {
      return null;
    }
    final preferred = preferredDoctorId?.trim();
    if (preferred != null &&
        preferred.isNotEmpty &&
        slot.availableDoctorIds.contains(preferred)) {
      return preferred;
    }
    return slot.availableDoctorIds.first;
  }

  static int openSlotCount(List<AppointmentBookingTimeSlot> slots) {
    return slots
        .where((slot) => slot.status != AppointmentBookingSlotStatus.locked)
        .length;
  }

  static AppointmentBookingSlotStatus _resolveStatus(
    List<String> availableDoctorIds,
    String? preferredDoctorId,
  ) {
    if (availableDoctorIds.isEmpty) {
      return AppointmentBookingSlotStatus.locked;
    }
    final preferred = preferredDoctorId?.trim();
    if (preferred == null || preferred.isEmpty) {
      return AppointmentBookingSlotStatus.available;
    }
    if (availableDoctorIds.contains(preferred)) {
      return AppointmentBookingSlotStatus.preferred;
    }
    return AppointmentBookingSlotStatus.alternate;
  }

  static bool _isDoctorFree({
    required String doctorId,
    required DateTime start,
    required DateTime end,
    required List<AppointmentListItem> appointments,
  }) {
    for (final appointment in appointments) {
      if (_blocksScheduling(appointment)) {
        continue;
      }
      final appointmentDoctorId = appointment.doctorId?.trim();
      if (appointmentDoctorId == null ||
          appointmentDoctorId.isEmpty ||
          appointmentDoctorId != doctorId) {
        continue;
      }
      if (_timesOverlap(
        start,
        end,
        appointment.startTime.toLocal(),
        appointment.endTime.toLocal(),
      )) {
        return false;
      }
    }
    return true;
  }

  static bool _blocksScheduling(AppointmentListItem item) {
    return item.status == AppointmentStatus.cancelled ||
        item.status == AppointmentStatus.noShow;
  }

  static bool _timesOverlap(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  static ({DateTime from, DateTime to}) dayFetchRange(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return (from: start, to: start.add(const Duration(days: 1)));
  }

  static ({DateTime from, DateTime to}) multiDayFetchRange(
    List<DateTime> days,
  ) {
    if (days.isEmpty) {
      final now = clock.now();
      final start = DateTime(now.year, now.month, now.day);
      return (from: start, to: start.add(const Duration(days: 1)));
    }
    final sorted = [...days]..sort((a, b) => a.compareTo(b));
    final first = DateTime(
      sorted.first.year,
      sorted.first.month,
      sorted.first.day,
    );
    final last = DateTime(sorted.last.year, sorted.last.month, sorted.last.day);
    return (from: first, to: last.add(const Duration(days: 1)));
  }

  static int defaultSlotMinutes(int? settingsDefault) {
    final candidate =
        settingsDefault ??
        AppointmentCalendarDisplay.defaultTimeIntervalMinutes;
    return AppointmentCalendarDisplay.supportedTimeIntervalMinutes.contains(
          candidate,
        )
        ? candidate
        : AppointmentCalendarDisplay.defaultTimeIntervalMinutes;
  }
}
