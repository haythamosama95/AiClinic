import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';

/// Wait time in minutes for [item] at [now] (web `getWaitMinutes`).
int queueWaitMinutes(AppointmentListItem item, DateTime now) {
  return AppointmentQueueDisplay.estimateWaitDuration(item, now: now).inMinutes;
}

/// Whether [item]'s scheduled slot has passed without a terminal/in-progress status
/// (web `isOverdue`).
bool queueIsOverdue(AppointmentListItem item, DateTime now) {
  return switch (item.status) {
    AppointmentStatus.completed ||
    AppointmentStatus.cancelled ||
    AppointmentStatus.noShow ||
    AppointmentStatus.inProgress => false,
    _ => item.startTime.isBefore(now),
  };
}

/// Triage sort: overdue scheduled first, then status priority, then slot time
/// (web `sortAppointmentsForTriage`; no `arrived` — `checkedIn` leads).
List<AppointmentListItem> queueSortForTriage(List<AppointmentListItem> items, DateTime now) {
  final sorted = List<AppointmentListItem>.of(items);
  sorted.sort((a, b) {
    final aOverdue = queueIsOverdue(a, now) && a.status == AppointmentStatus.scheduled ? 1 : 0;
    final bOverdue = queueIsOverdue(b, now) && b.status == AppointmentStatus.scheduled ? 1 : 0;
    if (aOverdue != bOverdue) {
      return bOverdue - aOverdue;
    }
    if (aOverdue == 1 && bOverdue == 1) {
      return _queueMinutesOverdue(b, now).compareTo(_queueMinutesOverdue(a, now));
    }
    final orderDiff = _triageStatusOrder(a.status) - _triageStatusOrder(b.status);
    if (orderDiff != 0) {
      return orderDiff;
    }
    return a.startTime.compareTo(b.startTime);
  });
  return sorted;
}

/// Status-chip filter; an empty [filters] set returns [items] unchanged
/// (web `filterByStatusChip`).
List<AppointmentListItem> queueFilterByStatus(List<AppointmentListItem> items, Set<AppointmentStatus> filters) {
  if (filters.isEmpty) {
    return items;
  }
  return items.where((item) => filters.contains(item.status)).toList(growable: false);
}

/// Checked-in patients sorted by longest wait first (web `getCheckedInPatients`).
List<AppointmentListItem> queueCheckedInPatients(List<AppointmentListItem> items, DateTime now) {
  final checkedIn = items.where((item) => item.status == AppointmentStatus.checkedIn).toList();
  checkedIn.sort((a, b) => queueWaitMinutes(b, now).compareTo(queueWaitMinutes(a, now)));
  return checkedIn;
}

int _queueMinutesOverdue(AppointmentListItem item, DateTime now) {
  if (!queueIsOverdue(item, now)) {
    return 0;
  }
  return now.difference(item.startTime).inMinutes;
}

int _triageStatusOrder(AppointmentStatus status) {
  return switch (status) {
    AppointmentStatus.checkedIn => 0,
    AppointmentStatus.inProgress => 1,
    AppointmentStatus.confirmed => 2,
    AppointmentStatus.scheduled => 3,
    AppointmentStatus.completed => 4,
    AppointmentStatus.cancelled => 5,
    AppointmentStatus.noShow => 6,
    AppointmentStatus.unknown => 7,
  };
}

/// Idle minutes for an available doctor derived from their latest completed visit
/// today (web `getIdleMinutes` analog when `idleSince` is unavailable).
int queueDoctorIdleMinutes(QueueShiftDoctor doctor, List<AppointmentListItem> appointments, {required DateTime now}) {
  DateTime? idleSince;
  for (final item in appointments) {
    if (item.doctorId != doctor.id || item.status != AppointmentStatus.completed) {
      continue;
    }
    final endedAt = item.updatedAt ?? item.endTime;
    if (idleSince == null || endedAt.isAfter(idleSince)) {
      idleSince = endedAt;
    }
  }
  if (idleSince == null) {
    return 0;
  }
  final minutes = now.difference(idleSince).inMinutes;
  return minutes > 0 ? minutes : 0;
}

/// Doctor lag minutes for the doctors panel (web `getDoctorLagMinutes`).
int queueDoctorLagMinutes(QueueShiftDoctor doctor, List<AppointmentListItem> appointments, {required DateTime now}) {
  final inProgress = AppointmentQueueDisplay.inProgressAppointmentForDoctor(doctor.id, appointments);
  if (inProgress != null) {
    final startedAt = inProgress.inProgressAt ?? inProgress.updatedAt;
    if (startedAt != null) {
      final elapsed = now.difference(startedAt).inMinutes;
      return elapsed > 20 ? elapsed - 20 : 0;
    }
    return 0;
  }

  final pending = appointments
      .where((item) => item.status == AppointmentStatus.checkedIn && item.doctorId == doctor.id)
      .length;
  if (pending > 2) {
    return 15 + pending * 5;
  }
  return 0;
}
