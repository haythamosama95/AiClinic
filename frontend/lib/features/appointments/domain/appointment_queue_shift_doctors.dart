import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_list_item.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

/// Doctor staffed on a shift at a given appointment time.
@immutable
class QueueShiftDoctor {
  const QueueShiftDoctor({required this.id, required this.name});

  final String id;
  final String name;
}

/// One doctor row in the queue appointments card.
@immutable
class QueueAppointmentDoctorEntry {
  const QueueAppointmentDoctorEntry({required this.name, required this.isPatientChoice});

  final String name;
  final bool isPatientChoice;
}

/// Doctor column content for a queue appointment row.
@immutable
class QueueAppointmentDoctorPresentation {
  const QueueAppointmentDoctorPresentation({required this.entries});

  final List<QueueAppointmentDoctorEntry> entries;

  bool get hasPatientChoice => entries.any((entry) => entry.isPatientChoice);

  String get displayNames => entries.map((entry) => entry.name).join(', ');

  String get avatarName => entries.isEmpty ? '?' : entries.first.name;
}

/// Resolves doctors staffed on shifts for queue display (V1-4 + V1-7).
@immutable
class AppointmentQueueShiftDoctorLookup {
  const AppointmentQueueShiftDoctorLookup({
    required this.organizationTimezone,
    required this.shifts,
    required this.doctorNamesByNormalizedName,
    required this.doctorIdsByNormalizedName,
  });

  final String organizationTimezone;
  final List<ShiftListItem> shifts;
  final Map<String, String> doctorNamesByNormalizedName;
  final Map<String, String> doctorIdsByNormalizedName;

  static const empty = AppointmentQueueShiftDoctorLookup(
    organizationTimezone: 'UTC',
    shifts: [],
    doctorNamesByNormalizedName: {},
    doctorIdsByNormalizedName: {},
  );

  factory AppointmentQueueShiftDoctorLookup.fromShiftsAndDoctors({
    required String organizationTimezone,
    required List<ShiftListItem> shifts,
    required List<StaffListItem> doctors,
  }) {
    final namesByKey = <String, String>{};
    final idsByKey = <String, String>{};
    for (final doctor in doctors) {
      if (doctor.role != StaffRole.doctor) {
        continue;
      }
      final name = doctor.fullName.trim();
      if (name.isEmpty) {
        continue;
      }
      final key = name.toLowerCase();
      namesByKey[key] = name;
      idsByKey[key] = doctor.id;
    }

    final staffedShifts = shifts.where(_isStaffedShift).toList(growable: false);

    return AppointmentQueueShiftDoctorLookup(
      organizationTimezone: organizationTimezone,
      shifts: staffedShifts,
      doctorNamesByNormalizedName: namesByKey,
      doctorIdsByNormalizedName: idsByKey,
    );
  }

  static bool _isStaffedShift(ShiftListItem shift) {
    return shift.status != ShiftStatus.cancelled && !shift.isUnassigned && shift.assigneeNames.isNotEmpty;
  }

  /// Doctors on shifts covering [referenceUtc] in organization local time.
  ///
  /// Falls back to all staffed shifts on the same calendar day when none cover
  /// [referenceUtc], so the queue sidebar still lists today's shift doctors.
  List<QueueShiftDoctor> doctorsOnCurrentShiftAt(DateTime referenceUtc) {
    final covering = _doctorNamesOnShiftAt(referenceUtc, requireCoveringInstant: true);
    final names = covering.isEmpty ? _doctorNamesOnShiftAt(referenceUtc, requireCoveringInstant: false) : covering;
    return _queueShiftDoctorsForNames(names);
  }

  /// Doctors on an active shift covering [appointmentStartUtc] in org local time.
  List<QueueShiftDoctor> doctorsOnShiftAt(DateTime appointmentStartUtc) {
    return _queueShiftDoctorsForNames(_doctorNamesOnShiftAt(appointmentStartUtc));
  }

  /// Doctor names on an active shift covering [appointmentStartUtc] in org local time.
  List<String> doctorNamesOnShiftAt(DateTime appointmentStartUtc) {
    return _doctorNamesOnShiftAt(appointmentStartUtc);
  }

  List<QueueShiftDoctor> _queueShiftDoctorsForNames(List<String> names) {
    final doctors = <QueueShiftDoctor>[];
    for (final name in names) {
      final id = _resolveDoctorId(name);
      if (id == null) {
        continue;
      }
      doctors.add(QueueShiftDoctor(id: id, name: name));
    }
    doctors.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return doctors;
  }

  List<String> _doctorNamesOnShiftAt(DateTime appointmentStartUtc, {bool requireCoveringInstant = true}) {
    ensureAppointmentTimezonesInitialized();
    final location = tz.getLocation(organizationTimezone);
    final localStart = tz.TZDateTime.from(appointmentStartUtc.toUtc(), location);
    final appointmentDay = DateTime(localStart.year, localStart.month, localStart.day);
    final appointmentMinutes = localStart.hour * 60 + localStart.minute;

    final names = <String>{};
    for (final shift in shifts) {
      if (!_isSameCalendarDay(shift.shiftDate, appointmentDay)) {
        continue;
      }
      final shiftStart = _parseClockMinutes(shift.startTime);
      final shiftEnd = _parseClockMinutes(shift.endTime);
      if (shiftStart == null || shiftEnd == null) {
        continue;
      }
      if (requireCoveringInstant && (appointmentMinutes < shiftStart || appointmentMinutes >= shiftEnd)) {
        continue;
      }
      for (final assignee in shift.assigneeNames) {
        final doctorName = _resolveDoctorName(assignee);
        if (doctorName != null) {
          names.add(doctorName);
        }
      }
    }

    final sorted = names.toList(growable: false)..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  QueueAppointmentDoctorPresentation presentationFor(AppointmentListItem item) {
    final assignedName = item.doctorName?.trim();
    if (item.doctorId != null && assignedName != null && assignedName.isNotEmpty) {
      final isPatientChoice = _isPatientChosenDoctor(item);
      return QueueAppointmentDoctorPresentation(
        entries: [QueueAppointmentDoctorEntry(name: assignedName, isPatientChoice: isPatientChoice)],
      );
    }

    return const QueueAppointmentDoctorPresentation(
      entries: [QueueAppointmentDoctorEntry(name: 'No preferred doctor', isPatientChoice: false)],
    );
  }

  /// Patient-selected doctor at booking — still unassigned until visit starts.
  static bool _isPatientChosenDoctor(AppointmentListItem item) {
    return switch (item.status) {
      AppointmentStatus.scheduled || AppointmentStatus.confirmed || AppointmentStatus.checkedIn => true,
      _ => false,
    };
  }

  String summaryLabelFor(AppointmentListItem item) => presentationFor(item).displayNames;

  String? _resolveDoctorName(String assigneeName) {
    return doctorNamesByNormalizedName[assigneeName.trim().toLowerCase()];
  }

  String? _resolveDoctorId(String doctorName) {
    return doctorIdsByNormalizedName[doctorName.trim().toLowerCase()];
  }

  static bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static int? _parseClockMinutes(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }
}
