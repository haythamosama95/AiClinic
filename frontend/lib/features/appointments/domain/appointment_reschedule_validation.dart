import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';

/// Client-side checks before confirming a calendar drag reschedule (V1-4 US6).
class AppointmentRescheduleValidation {
  AppointmentRescheduleValidation._();

  static bool isNoOpMove({required AppointmentListItem appointment, required DateTime newStart}) {
    return _isSameInstant(newStart.toLocal(), appointment.startTime);
  }

  static bool isNoOpResize({
    required AppointmentListItem appointment,
    required DateTime newStart,
    required DateTime newEnd,
  }) {
    return isNoOpMove(appointment: appointment, newStart: newStart) &&
        _isSameInstant(newEnd.toLocal(), appointment.endTime);
  }

  static String? validateMove({
    required AppointmentListItem appointment,
    required DateTime newStart,
    DateTime? newEnd,
    required BranchWorkingSchedule schedule,
    required List<AppointmentListItem> branchAppointments,
  }) {
    if (!canRescheduleAppointment(appointment)) {
      return 'Only scheduled appointments can be moved. Confirmed appointments must be cancelled and re-booked.';
    }

    final originalDurationMinutes = appointment.endTime.difference(appointment.startTime).inMinutes;
    if (originalDurationMinutes < 5) {
      return 'Appointment duration is too short to reschedule.';
    }

    final localNewStart = newStart.toLocal();
    final localNewEnd = (newEnd ?? localNewStart.add(Duration(minutes: originalDurationMinutes))).toLocal();
    final durationMinutes = localNewEnd.difference(localNewStart).inMinutes;

    if (!localNewEnd.isAfter(localNewStart)) {
      return 'End time must be after start time.';
    }

    if (durationMinutes < 5) {
      return 'Appointment duration is too short to reschedule.';
    }

    final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
      schedule: schedule,
      startTime: localNewStart,
      durationMinutes: durationMinutes,
    );
    if (hoursMessage != null) {
      return hoursMessage;
    }

    if (!AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: localNewStart, end: localNewEnd)) {
      return 'Appointment must be within branch working hours.';
    }

    final overlapMessage = _overlapMessage(
      appointment: appointment,
      newStart: localNewStart,
      newEnd: localNewEnd,
      branchAppointments: branchAppointments,
    );
    if (overlapMessage != null) {
      return overlapMessage;
    }

    final patientDayMessage = _patientSameDayMessage(
      appointment: appointment,
      newStart: localNewStart,
      branchAppointments: branchAppointments,
    );
    if (patientDayMessage != null) {
      return patientDayMessage;
    }

    return null;
  }

  static String? validateDoctorResourceMove({
    required AppointmentListItem appointment,
    required String? targetDoctorId,
  }) {
    final currentDoctorId = _normalizedId(appointment.doctorId);
    final nextDoctorId = _normalizedId(targetDoctorId);
    if (currentDoctorId == nextDoctorId) {
      return null;
    }
    return 'Moving an appointment to another doctor is not supported. Cancel and re-book to change the doctor.';
  }

  static bool _isSameInstant(DateTime a, DateTime b) {
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }

  static String? _normalizedId(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static bool _blocksScheduling(AppointmentListItem item) {
    return item.status == AppointmentStatus.cancelled || item.status == AppointmentStatus.noShow;
  }

  static bool _timesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  static String? _overlapMessage({
    required AppointmentListItem appointment,
    required DateTime newStart,
    required DateTime newEnd,
    required List<AppointmentListItem> branchAppointments,
  }) {
    for (final other in branchAppointments) {
      if (other.id == appointment.id || _blocksScheduling(other)) {
        continue;
      }

      final otherStart = other.startTime.toLocal();
      final otherEnd = other.endTime.toLocal();
      if (!_timesOverlap(newStart, newEnd, otherStart, otherEnd)) {
        continue;
      }

      final doctorId = _normalizedId(appointment.doctorId);
      if (doctorId != null && _normalizedId(other.doctorId) == doctorId) {
        return 'The doctor is not available at this time (overlaps with ${other.patientName}).';
      }

      return 'This time overlaps another appointment (${other.patientName}).';
    }

    return null;
  }

  static String? _patientSameDayMessage({
    required AppointmentListItem appointment,
    required DateTime newStart,
    required List<AppointmentListItem> branchAppointments,
  }) {
    final newDay = DateTime(newStart.year, newStart.month, newStart.day);

    for (final other in branchAppointments) {
      if (other.id == appointment.id || _blocksScheduling(other)) {
        continue;
      }
      if (other.patientId != appointment.patientId) {
        continue;
      }

      final otherDay = DateTime(
        other.startTime.toLocal().year,
        other.startTime.toLocal().month,
        other.startTime.toLocal().day,
      );
      if (otherDay == newDay) {
        return 'This patient already has an appointment on the same day.';
      }
    }

    return null;
  }
}
