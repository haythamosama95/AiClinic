import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/domain/queue_shift_doctors.dart';

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
    return _queueWaitMinutes(item, now) > longWaitThresholdMinutes;
  }).toList(growable: false);

  final overdue = appointments
      .where(
        (item) =>
            _queueIsOverdue(item, now) &&
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
    return _queueWaitMinutes(item, now) >
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
            _queueIsOverdue(item, now) &&
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

int _queueWaitMinutes(AppointmentListItem item, DateTime now) {
  return AppointmentQueueDisplay.estimateWaitDuration(item, now: now).inMinutes;
}

bool _queueIsOverdue(AppointmentListItem item, DateTime now) {
  return switch (item.status) {
    AppointmentStatus.completed ||
    AppointmentStatus.cancelled ||
    AppointmentStatus.noShow ||
    AppointmentStatus.inProgress =>
      false,
    _ => item.startTime.isBefore(now),
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
