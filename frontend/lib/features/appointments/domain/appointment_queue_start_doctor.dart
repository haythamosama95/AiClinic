import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter/foundation.dart';

/// Doctor option when starting a checked-in appointment from the queue.
@immutable
class QueueStartDoctorOption {
  const QueueStartDoctorOption({required this.id, required this.name, required this.isBusy});

  final String id;
  final String name;
  final bool isBusy;
}

/// Resolves which doctor should take a checked-in appointment when it starts.
abstract final class AppointmentQueueStartDoctor {
  /// Whether [doctorId] already has another in-progress appointment.
  static bool isDoctorBusy({
    required String doctorId,
    required String excludeAppointmentId,
    required Iterable<AppointmentListItem> items,
  }) {
    return items.any(
      (other) =>
          other.id != excludeAppointmentId &&
          other.status == AppointmentStatus.inProgress &&
          other.doctorId == doctorId,
    );
  }

  /// Shift doctors available when [item] has no assigned doctor.
  static List<QueueStartDoctorOption> shiftOptionsFor({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final onShift = shiftLookup.doctorsOnShiftAt(item.startTime);
    return [
      for (final doctor in onShift)
        QueueStartDoctorOption(
          id: doctor.id,
          name: doctor.name,
          isBusy: isDoctorBusy(doctorId: doctor.id, excludeAppointmentId: item.id, items: siblingAppointments),
        ),
    ];
  }

  /// Tooltip / disabled reason before starting a checked-in appointment.
  static String? blockReasonForStart({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    AppointmentQueueShiftDoctorLookup shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
  }) {
    if (item.status != AppointmentStatus.checkedIn) {
      return null;
    }

    final assignedDoctorId = item.doctorId?.trim();
    if (assignedDoctorId != null && assignedDoctorId.isNotEmpty) {
      if (isDoctorBusy(doctorId: assignedDoctorId, excludeAppointmentId: item.id, items: siblingAppointments)) {
        final doctorLabel = item.doctorName?.trim().isNotEmpty == true ? item.doctorName!.trim() : 'This doctor';
        return '$doctorLabel already has a patient in progress. Complete that visit before starting another.';
      }
      return null;
    }

    final options = shiftOptionsFor(item: item, siblingAppointments: siblingAppointments, shiftLookup: shiftLookup);
    if (options.isEmpty) {
      return 'No doctor is on shift for this appointment time.';
    }
    if (options.length == 1) {
      final doctor = options.first;
      if (doctor.isBusy) {
        return '${doctor.name} already has a patient in progress. Complete that visit before starting another.';
      }
      return null;
    }

    if (options.every((option) => option.isBusy)) {
      return 'All doctors on shift already have patients in progress.';
    }
    return null;
  }

  /// Doctor to assign before advancing to in progress.
  ///
  /// Returns the assigned doctor id when [item] already has one, the only shift
  /// doctor when exactly one is staffed, or `null` when the caller must prompt.
  static String? autoSelectedDoctorId({
    required AppointmentListItem item,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final assignedDoctorId = item.doctorId?.trim();
    if (assignedDoctorId != null && assignedDoctorId.isNotEmpty) {
      return assignedDoctorId;
    }

    final onShift = shiftLookup.doctorsOnShiftAt(item.startTime);
    if (onShift.length == 1) {
      return onShift.first.id;
    }
    return null;
  }

  /// Whether the user must pick a doctor before starting.
  static bool requiresDoctorPicker({
    required AppointmentListItem item,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final assignedDoctorId = item.doctorId?.trim();
    if (assignedDoctorId != null && assignedDoctorId.isNotEmpty) {
      return false;
    }
    return shiftLookup.doctorsOnShiftAt(item.startTime).length > 1;
  }
}
