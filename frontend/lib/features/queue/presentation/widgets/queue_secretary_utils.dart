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
    AppointmentStatus.inProgress =>
      false,
    _ => item.startTime.isBefore(now),
  };
}

/// Triage sort: overdue scheduled first, then status priority, then slot time
/// (web `sortAppointmentsForTriage`; no `arrived` — `checkedIn` leads).
List<AppointmentListItem> queueSortForTriage(
  List<AppointmentListItem> items,
  DateTime now,
) {
  final sorted = List<AppointmentListItem>.of(items);
  sorted.sort((a, b) {
    final aOverdue =
        queueIsOverdue(a, now) && a.status == AppointmentStatus.scheduled ? 1 : 0;
    final bOverdue =
        queueIsOverdue(b, now) && b.status == AppointmentStatus.scheduled ? 1 : 0;
    if (aOverdue != bOverdue) {
      return bOverdue - aOverdue;
    }
    if (aOverdue == 1 && bOverdue == 1) {
      return _queueMinutesOverdue(b, now).compareTo(_queueMinutesOverdue(a, now));
    }
    final orderDiff =
        _triageStatusOrder(a.status) - _triageStatusOrder(b.status);
    if (orderDiff != 0) {
      return orderDiff;
    }
    return a.startTime.compareTo(b.startTime);
  });
  return sorted;
}

/// Status-chip filter; an empty [filters] set returns [items] unchanged
/// (web `filterByStatusChip`).
List<AppointmentListItem> queueFilterByStatus(
  List<AppointmentListItem> items,
  Set<AppointmentStatus> filters,
) {
  if (filters.isEmpty) {
    return items;
  }
  return items.where((item) => filters.contains(item.status)).toList(growable: false);
}

/// Checked-in patients sorted by longest wait first (web `getCheckedInPatients`).
List<AppointmentListItem> queueCheckedInPatients(
  List<AppointmentListItem> items,
  DateTime now,
) {
  final checkedIn = items
      .where((item) => item.status == AppointmentStatus.checkedIn)
      .toList();
  checkedIn.sort(
    (a, b) => queueWaitMinutes(b, now).compareTo(queueWaitMinutes(a, now)),
  );
  return checkedIn;
}

/// Compact alert line for the queue health banner (web `buildAlertSummary`).
///
/// Uses shorter copy than [queueHealthIssues] and includes doctor lag when present.
String? queueAlertSummary(
  List<AppointmentListItem> appointments, {
  required AppointmentQueueShiftDoctorLookup shiftLookup,
  required DateTime now,
}) {
  const longWaitThresholdMinutes = 20;

  final longWaits = appointments.where((item) {
    if (item.status != AppointmentStatus.checkedIn) {
      return false;
    }
    return queueWaitMinutes(item, now) > longWaitThresholdMinutes;
  }).toList(growable: false);

  final overdue = appointments
      .where(
        (item) =>
            queueIsOverdue(item, now) &&
            item.status == AppointmentStatus.scheduled,
      )
      .toList(growable: false);

  final shiftDoctors = shiftLookup.doctorsOnCurrentShiftAt(now);
  final laggingDoctors = <({QueueShiftDoctor doctor, int lag})>[];
  for (final doctor in shiftDoctors) {
    final lag = _queueDoctorLagMinutes(doctor, appointments, now: now);
    if (lag >= 15) {
      laggingDoctors.add((doctor: doctor, lag: lag));
    }
  }
  laggingDoctors.sort((a, b) => b.lag.compareTo(a.lag));

  final parts = <String>[];
  if (longWaits.isNotEmpty) {
    final count = longWaits.length;
    parts.add('$count long wait${count > 1 ? 's' : ''}');
  }
  if (overdue.isNotEmpty) {
    parts.add('${overdue.length} overdue');
  }
  if (laggingDoctors.isNotEmpty) {
    final top = laggingDoctors.first;
    final lastName = _doctorLastName(top.doctor.name);
    parts.add('$lastName +${top.lag} min behind');
  }

  return parts.isEmpty ? null : parts.join(' · ');
}

/// Detailed queue health issues for the alert banner (web `getQueueHealthIssues`).
List<String> queueHealthIssues(
  List<AppointmentListItem> appointments, {
  required AppointmentQueueShiftDoctorLookup shiftLookup,
  required DateTime now,
}) {
  final issues = <String>[];

  final longWaits = appointments.where((item) {
    if (item.status != AppointmentStatus.checkedIn) {
      return false;
    }
    return queueWaitMinutes(item, now) >
        AppointmentQueueDisplay.waitCriticalMinutes;
  }).toList(growable: false);

  if (longWaits.isNotEmpty) {
    final count = longWaits.length;
    issues.add(
      '$count patient${count > 1 ? 's' : ''} waiting over '
      '${AppointmentQueueDisplay.waitCriticalMinutes} minutes',
    );
  }

  final overdue = appointments
      .where(
        (item) =>
            queueIsOverdue(item, now) &&
            item.status == AppointmentStatus.scheduled,
      )
      .toList(growable: false);

  if (overdue.isNotEmpty) {
    final count = overdue.length;
    issues.add(
      '$count overdue appointment${count > 1 ? 's' : ''} not yet arrived',
    );
  }

  final shiftDoctors = shiftLookup.doctorsOnCurrentShiftAt(now);
  final availableDoctors = shiftDoctors
      .where(
        (doctor) =>
            AppointmentQueueDisplay.inProgressAppointmentForDoctor(
              doctor.id,
              appointments,
            ) ==
            null,
      )
      .length;

  final queueLength = appointments
      .where((item) => item.status == AppointmentStatus.checkedIn)
      .length;

  if (queueLength > 0 && availableDoctors == 0) {
    issues.add('No doctors currently available — queue backing up');
  }

  return issues;
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

int _queueDoctorLagMinutes(
  QueueShiftDoctor doctor,
  List<AppointmentListItem> appointments, {
  required DateTime now,
}) {
  final inProgress = AppointmentQueueDisplay.inProgressAppointmentForDoctor(
    doctor.id,
    appointments,
  );
  if (inProgress != null) {
    final startedAt = inProgress.inProgressAt ?? inProgress.updatedAt;
    if (startedAt != null) {
      final elapsed = now.difference(startedAt).inMinutes;
      return elapsed > 20 ? elapsed - 20 : 0;
    }
    return 0;
  }

  final pending = appointments
      .where(
        (item) =>
            item.status == AppointmentStatus.checkedIn &&
            item.doctorId == doctor.id,
      )
      .length;
  if (pending > 2) {
    return 15 + pending * 5;
  }
  return 0;
}

String _doctorLastName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) {
    return fullName;
  }
  return parts.last;
}
