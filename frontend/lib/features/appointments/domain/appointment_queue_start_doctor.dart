import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter/foundation.dart';

/// Doctor option when starting a checked-in appointment from the queue.
@immutable
class QueueStartDoctorOption {
  const QueueStartDoctorOption({required this.id, required this.name, required this.isBusy, this.isPreferred = false});

  final String id;
  final String name;
  final bool isBusy;
  final bool isPreferred;
}

/// Resolves which doctor should take a checked-in appointment when it starts.
abstract final class AppointmentQueueStartDoctor {
  /// Whether [doctorId] already has another in-progress appointment.
  static bool isDoctorBusy({
    required String doctorId,
    required String excludeAppointmentId,
    required Iterable<AppointmentListItem> items,
  }) {
    final normalizedId = doctorId.trim();
    if (normalizedId.isEmpty) {
      return items.any(
        (other) =>
            other.id != excludeAppointmentId &&
            other.status == AppointmentStatus.inProgress &&
            (other.doctorId == null || other.doctorId!.trim().isEmpty),
      );
    }

    return items.any(
      (other) =>
          other.id != excludeAppointmentId &&
          other.status == AppointmentStatus.inProgress &&
          other.doctorId == normalizedId,
    );
  }

  /// Shift doctors available when [item] has no assigned doctor.
  static List<QueueStartDoctorOption> shiftOptionsFor({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final preferredDoctorId = item.doctorId?.trim();
    final onShift = shiftLookup.doctorsOnShiftAt(item.startTime);
    return [
      for (final doctor in onShift)
        QueueStartDoctorOption(
          id: doctor.id,
          name: doctor.name,
          isBusy: isDoctorBusy(doctorId: doctor.id, excludeAppointmentId: item.id, items: siblingAppointments),
          isPreferred: preferredDoctorId != null && preferredDoctorId.isNotEmpty && doctor.id == preferredDoctorId,
        ),
    ];
  }

  /// Doctors selectable when starting [item], including the preferred doctor when missing from shift.
  static List<QueueStartDoctorOption> optionsForStart({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final options = shiftOptionsFor(item: item, siblingAppointments: siblingAppointments, shiftLookup: shiftLookup);
    final preferredDoctorId = item.doctorId?.trim();
    if (preferredDoctorId == null || preferredDoctorId.isEmpty) {
      return options;
    }
    if (options.any((option) => option.id == preferredDoctorId)) {
      return options;
    }

    final preferredDoctorName = item.doctorName?.trim().isNotEmpty == true
        ? item.doctorName!.trim()
        : 'Preferred doctor';
    return [
      QueueStartDoctorOption(
        id: preferredDoctorId,
        name: preferredDoctorName,
        isBusy: isDoctorBusy(doctorId: preferredDoctorId, excludeAppointmentId: item.id, items: siblingAppointments),
        isPreferred: true,
      ),
      ...options,
    ];
  }

  /// Whether [item]'s assigned preferred doctor already has another in-progress patient.
  static bool isPreferredDoctorBusy({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
  }) {
    final assignedDoctorId = item.doctorId?.trim();
    if (assignedDoctorId == null || assignedDoctorId.isEmpty) {
      return false;
    }
    return isDoctorBusy(doctorId: assignedDoctorId, excludeAppointmentId: item.id, items: siblingAppointments);
  }

  /// Free doctors on shift when starting [item].
  static List<QueueStartDoctorOption> availableShiftOptionsFor({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    return shiftOptionsFor(
      item: item,
      siblingAppointments: siblingAppointments,
      shiftLookup: shiftLookup,
    ).where((option) => !option.isBusy).toList(growable: false);
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
      if (isPreferredDoctorBusy(item: item, siblingAppointments: siblingAppointments)) {
        final freeAlternatives = availableShiftOptionsFor(
          item: item,
          siblingAppointments: siblingAppointments,
          shiftLookup: shiftLookup,
        );
        if (freeAlternatives.isNotEmpty) {
          return null;
        }
        final doctorLabel = item.doctorName?.trim().isNotEmpty == true ? item.doctorName!.trim() : 'This doctor';
        return '$doctorLabel already has a patient in progress. Complete that visit before starting another.';
      }
      return null;
    }

    final unassignedInProgress = siblingAppointments.where(
      (other) =>
          other.id != item.id &&
          other.status == AppointmentStatus.inProgress &&
          (other.doctorId == null || other.doctorId!.trim().isEmpty),
    );
    if (unassignedInProgress.isNotEmpty) {
      return 'Another visit without an assigned doctor is already in progress. Complete that visit or assign a doctor before starting another.';
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

  /// Resolves the doctor id to use when starting without showing the picker.
  ///
  /// Returns the assigned doctor when present, otherwise the first free on-shift doctor.
  static String? autoResolveDoctorId({
    required AppointmentListItem item,
    required Iterable<AppointmentListItem> siblingAppointments,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
  }) {
    final assigned = item.doctorId?.trim();
    if (assigned != null && assigned.isNotEmpty) {
      return assigned;
    }
    final options = optionsForStart(
      item: item,
      siblingAppointments: siblingAppointments,
      shiftLookup: shiftLookup,
    );
    return options.where((option) => !option.isBusy).firstOrNull?.id;
  }

  /// Whether the user must confirm a doctor in the picker before starting.
  static bool requiresDoctorPicker({
    required AppointmentListItem item,
    required AppointmentQueueShiftDoctorLookup shiftLookup,
    Iterable<AppointmentListItem> siblingAppointments = const [],
  }) {
    if (item.status != AppointmentStatus.checkedIn) {
      return false;
    }
    if (blockReasonForStart(item: item, siblingAppointments: siblingAppointments, shiftLookup: shiftLookup) != null) {
      return false;
    }
    final assignedDoctorId = item.doctorId?.trim();
    if (assignedDoctorId != null && assignedDoctorId.isNotEmpty) {
      return isPreferredDoctorBusy(item: item, siblingAppointments: siblingAppointments) &&
          availableShiftOptionsFor(
            item: item,
            siblingAppointments: siblingAppointments,
            shiftLookup: shiftLookup,
          ).isNotEmpty;
    }
    return optionsForStart(
      item: item,
      siblingAppointments: siblingAppointments,
      shiftLookup: shiftLookup,
    ).any((option) => !option.isBusy);
  }
}
