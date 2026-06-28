import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:timezone/timezone.dart' as tz;

/// Appointment and visit scheduling helpers for dev clinic seeding.
abstract final class DevClinicSeedSchedule {
  static const appointmentDayOffsets = [-2, -1, 0, 1, 2, 3, 4, 5];
  static const minAppointmentDurationMinutes = 30;
  static const maxAppointmentDurationMinutes = 90;
  static const firstSlotLocalHour = 9;
  static const firstSlotLocalMinute = 0;
  static const branchCloseLocalHour = 21;

  static const seedableAppointmentStatuses = <AppointmentStatus>[
    AppointmentStatus.scheduled,
    AppointmentStatus.confirmed,
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
    AppointmentStatus.completed,
    AppointmentStatus.cancelled,
    AppointmentStatus.noShow,
  ];

  static const seedablePatientGenders = <PatientGender>[PatientGender.male, PatientGender.female];

  static const seedableMaritalStatuses = PatientMaritalStatus.values;

  static DateTime patientDateOfBirth(int seedKey) {
    final year = 1955 + (seedKey % 45);
    final month = (seedKey % 12) + 1;
    final day = (seedKey % 27) + 1;
    return DateTime(year, month, day);
  }

  static PatientGender patientGender(int seedKey) {
    return seedablePatientGenders[seedKey % seedablePatientGenders.length];
  }

  static PatientMaritalStatus patientMaritalStatus(int seedKey) {
    return seedableMaritalStatuses[seedKey % seedableMaritalStatuses.length];
  }

  static String patientNotes({required String branchCode, required int patientIndex}) {
    return 'Dev seed patient $branchCode #$patientIndex — allergies reviewed, emergency contact on file.';
  }

  /// Statuses allowed for appointments on a calendar day relative to "today" in [timezone].
  ///
  /// - Before today: completed, cancelled, or no-show only.
  /// - Today: confirmed and queue-active statuses.
  /// - After today: scheduled, confirmed, or cancelled only.
  static List<AppointmentStatus> allowedStatusesForCalendarDayRelation(DevClinicSeedCalendarDayRelation relation) {
    return switch (relation) {
      DevClinicSeedCalendarDayRelation.past => const [
        AppointmentStatus.completed,
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
      ],
      DevClinicSeedCalendarDayRelation.today => const [
        AppointmentStatus.confirmed,
        AppointmentStatus.checkedIn,
        AppointmentStatus.inProgress,
      ],
      DevClinicSeedCalendarDayRelation.future => const [
        AppointmentStatus.scheduled,
        AppointmentStatus.confirmed,
        AppointmentStatus.cancelled,
      ],
    };
  }

  static DevClinicSeedCalendarDayRelation calendarDayRelationFor({
    required DateTime startTimeUtc,
    required String timezone,
    DateTime? referenceUtc,
  }) {
    ensureAppointmentTimezonesInitialized();
    final ref = (referenceUtc ?? DateTime.now()).toUtc();
    final location = tz.getLocation(timezone);
    final apptLocal = tz.TZDateTime.from(startTimeUtc.toUtc(), location);
    final todayLocal = tz.TZDateTime.from(ref, location);
    final apptDay = DateTime(apptLocal.year, apptLocal.month, apptLocal.day);
    final today = DateTime(todayLocal.year, todayLocal.month, todayLocal.day);
    if (apptDay.isBefore(today)) {
      return DevClinicSeedCalendarDayRelation.past;
    }
    if (apptDay.isAtSameMomentAs(today)) {
      return DevClinicSeedCalendarDayRelation.today;
    }
    return DevClinicSeedCalendarDayRelation.future;
  }

  static List<AppointmentStatus> allowedStatusesForDayOffset(int dayOffset) {
    final relation = switch (dayOffset) {
      < 0 => DevClinicSeedCalendarDayRelation.past,
      0 => DevClinicSeedCalendarDayRelation.today,
      _ => DevClinicSeedCalendarDayRelation.future,
    };
    return allowedStatusesForCalendarDayRelation(relation);
  }

  static List<AppointmentStatus> allowedStatusesForStartTime({
    required DateTime startTimeUtc,
    required String timezone,
    DateTime? referenceUtc,
  }) {
    final relation = calendarDayRelationFor(startTimeUtc: startTimeUtc, timezone: timezone, referenceUtc: referenceUtc);
    return allowedStatusesForCalendarDayRelation(relation);
  }

  static AppointmentStatus appointmentStatusFor({
    required DateTime startTimeUtc,
    required String timezone,
    required int seedKey,
    DateTime? referenceUtc,
  }) {
    final allowed = allowedStatusesForStartTime(
      startTimeUtc: startTimeUtc,
      timezone: timezone,
      referenceUtc: referenceUtc,
    );
    final index = seedKey % allowed.length;
    return allowed[index < 0 ? index + allowed.length : index];
  }

  /// Deterministic appointment length in [minAppointmentDurationMinutes, maxAppointmentDurationMinutes].
  static int appointmentDurationMinutesFor(int seedKey) {
    final span = maxAppointmentDurationMinutes - minAppointmentDurationMinutes + 1;
    return minAppointmentDurationMinutes + (seedKey % span);
  }

  /// Whether a seeded appointment gets a preferred doctor.
  ///
  /// - Today: odd [patientIndex] values are assigned; even values are unassigned (50/50).
  /// - Other days: roughly one in six omit doctor assignment (for unassigned UI/testing).
  static bool shouldAssignDoctorForAppointment({
    required int dayOffset,
    required int patientIndex,
    required int seedKey,
  }) {
    if (dayOffset == 0) {
      return patientIndex.isOdd;
    }
    return seedKey % 6 != 0;
  }

  /// Day offsets for shift seeding (today through five days ahead; past dates are read-only).
  static List<int> get shiftDayOffsets => appointmentDayOffsets.where((offset) => offset >= 0).toList(growable: false);

  static DateTime shiftDateLocal({required String timezone, required int dayOffset, DateTime? referenceUtc}) {
    ensureAppointmentTimezonesInitialized();
    final ref = (referenceUtc ?? DateTime.now()).toUtc();
    final location = tz.getLocation(timezone);
    final localNow = tz.TZDateTime.from(ref, location);
    final day = tz.TZDateTime(location, localNow.year, localNow.month, localNow.day).add(Duration(days: dayOffset));
    return DateTime(day.year, day.month, day.day);
  }

  /// Doctors staffed on a branch shift — matches appointment doctor assignment options.
  static List<String> shiftDoctorIdsForBranch({required String primaryDoctorId, required String? secondaryDoctorId}) {
    final primary = primaryDoctorId.trim();
    final ids = <String>[primary];
    final secondary = secondaryDoctorId?.trim();
    if (secondary != null && secondary.isNotEmpty && secondary != primary) {
      ids.add(secondary);
    }
    return ids;
  }

  static String shiftNotes({required String branchCode, required int dayOffset}) {
    return 'Dev seed shift for $branchCode (day $dayOffset).';
  }

  /// Visit-eligible statuses require a doctor; keep unassigned appointments bookable only.
  static AppointmentStatus appointmentTargetWithoutDoctor(AppointmentStatus target) {
    return switch (target) {
      AppointmentStatus.checkedIn ||
      AppointmentStatus.inProgress ||
      AppointmentStatus.completed => AppointmentStatus.confirmed,
      _ => target,
    };
  }

  /// Cumulative minutes before [patientIndex] on a single branch-day timeline.
  ///
  /// The backend rejects any overlapping slot in the same branch (regardless of doctor),
  /// so appointments must be packed sequentially rather than on parallel doctor tracks.
  static int minutesBeforePatient({required int dayOffset, required int patientIndex}) {
    var total = 0;
    for (var i = 1; i < patientIndex; i++) {
      total += appointmentDurationMinutesFor(i + dayOffset);
    }
    return total;
  }

  /// Whether a visit row should be created for the target appointment status.
  static bool shouldSeedVisit(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.checkedIn || AppointmentStatus.inProgress || AppointmentStatus.completed => true,
      _ => false,
    };
  }

  /// Whether the seeded visit should be completed (requires clinical note + treatment plan).
  static bool shouldCompleteVisit(AppointmentStatus status) {
    return status == AppointmentStatus.completed;
  }

  /// Visit documentation depth for eligible appointments.
  static DevClinicVisitDocumentationKind visitDocumentationFor({
    required AppointmentStatus status,
    required int seedKey,
  }) {
    if (!shouldSeedVisit(status)) {
      return DevClinicVisitDocumentationKind.none;
    }
    if (status == AppointmentStatus.completed) {
      return DevClinicVisitDocumentationKind.completedWithTreatment;
    }
    if (status == AppointmentStatus.inProgress) {
      return seedKey.isEven ? DevClinicVisitDocumentationKind.full : DevClinicVisitDocumentationKind.partial;
    }

    return switch (seedKey % 3) {
      0 => DevClinicVisitDocumentationKind.partial,
      1 => DevClinicVisitDocumentationKind.full,
      _ => DevClinicVisitDocumentationKind.none,
    };
  }

  static DateTime appointmentStartUtc({
    required String timezone,
    required int dayOffset,
    required int patientIndex,
    DateTime? referenceUtc,
  }) {
    ensureAppointmentTimezonesInitialized();
    final ref = (referenceUtc ?? DateTime.now()).toUtc();
    final location = tz.getLocation(timezone);
    final localNow = tz.TZDateTime.from(ref, location);
    final day = tz.TZDateTime(location, localNow.year, localNow.month, localNow.day).add(Duration(days: dayOffset));
    final durationMinutes = appointmentDurationMinutesFor(patientIndex + dayOffset);
    final trackOffsetMinutes = minutesBeforePatient(dayOffset: dayOffset, patientIndex: patientIndex);
    final startMinutes = firstSlotLocalHour * 60 + firstSlotLocalMinute + trackOffsetMinutes;
    final endMinutes = startMinutes + durationMinutes;
    final closeMinutes = branchCloseLocalHour * 60;
    if (endMinutes > closeMinutes) {
      throw StateError(
        'Dev seed appointment for patient $patientIndex ends after branch close '
        '(${DevClinicSeedSpec.branchCloseTime}). Reduce patients per branch or slot density.',
      );
    }

    final hour = startMinutes ~/ 60;
    final minute = startMinutes % 60;
    return tz.TZDateTime(location, day.year, day.month, day.day, hour, minute).toUtc();
  }

  static String appointmentNotes({
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
    required AppointmentStatus status,
  }) {
    return 'Dev seed $branchCode patient #$patientIndex day $dayOffset — ${status.label}.';
  }

  static ({String complaint, String history, String examination, String diagnosis, String plan})
  clinicalNoteContentFor({
    required DevClinicVisitDocumentationKind kind,
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
  }) {
    final label = '$branchCode #$patientIndex day $dayOffset';
    return switch (kind) {
      DevClinicVisitDocumentationKind.none => (
        complaint: '',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
      ),
      DevClinicVisitDocumentationKind.partial => (
        complaint: 'Patient $label reports mild symptoms for two days.',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
      ),
      DevClinicVisitDocumentationKind.full => (
        complaint: 'Patient $label reports intermittent discomfort.',
        history: 'Symptoms began three days ago without trauma.',
        examination: 'Vitals stable. No acute distress.',
        diagnosis: 'Likely viral upper respiratory infection.',
        plan: 'Hydration, rest, return if symptoms worsen.',
      ),
      DevClinicVisitDocumentationKind.completedWithTreatment => (
        complaint: 'Patient $label completed follow-up visit.',
        history: 'Prior visit two weeks ago for same complaint.',
        examination: 'Exam unremarkable. Labs reviewed.',
        diagnosis: 'Condition improving on current regimen.',
        plan: 'Continue medication, schedule routine follow-up.',
      ),
    };
  }

  static ({String medicationName, String dosage, String frequency, String duration, String notes}) treatmentPlanFor({
    required String branchCode,
    required int patientIndex,
  }) {
    return (
      medicationName: 'Dev Seed Rx $branchCode',
      dosage: '${(patientIndex % 3) + 1}00 mg',
      frequency: patientIndex.isEven ? 'Twice daily' : 'Once daily',
      duration: '${7 + (patientIndex % 4)} days',
      notes: 'Take with food. Dev seed treatment plan for patient #$patientIndex.',
    );
  }

  /// Whether advancing to [target] must pass through `in_progress` via status RPC.
  static bool requiresInProgressTransition(AppointmentStatus target) {
    return advancementPathTo(target).contains(AppointmentStatus.inProgress);
  }

  /// Whether seeding [status] for [seedKey] ends with the doctor still in an
  /// in-progress appointment (without completing the visit).
  static bool leavesDoctorInProgress({required AppointmentStatus status, required int seedKey}) {
    if (status == AppointmentStatus.completed) {
      return false;
    }
    if (status == AppointmentStatus.inProgress) {
      return true;
    }
    if (status == AppointmentStatus.checkedIn) {
      final documentation = visitDocumentationFor(status: status, seedKey: seedKey);
      return shouldSeedVisit(status) && documentation != DevClinicVisitDocumentationKind.none;
    }
    return false;
  }

  /// Downgrade visit-eligible targets when the doctor already has an active visit.
  static AppointmentStatus resolveTargetForDoctorAvailability({
    required AppointmentStatus target,
    required int seedKey,
    required bool doctorAlreadyInProgress,
  }) {
    if (!doctorAlreadyInProgress) {
      return target;
    }
    if (!leavesDoctorInProgress(status: target, seedKey: seedKey)) {
      return target;
    }
    return AppointmentStatus.confirmed;
  }

  /// Statuses to apply in order after `create_appointment` (starts at scheduled).
  static List<AppointmentStatus> advancementPathTo(AppointmentStatus target) {
    return switch (target) {
      AppointmentStatus.scheduled => const [],
      AppointmentStatus.confirmed => const [AppointmentStatus.confirmed],
      AppointmentStatus.checkedIn => const [AppointmentStatus.confirmed, AppointmentStatus.checkedIn],
      AppointmentStatus.inProgress => const [
        AppointmentStatus.confirmed,
        AppointmentStatus.checkedIn,
        AppointmentStatus.inProgress,
      ],
      AppointmentStatus.completed => const [
        AppointmentStatus.confirmed,
        AppointmentStatus.checkedIn,
        AppointmentStatus.inProgress,
      ],
      AppointmentStatus.cancelled => const [],
      AppointmentStatus.noShow => const [AppointmentStatus.confirmed, AppointmentStatus.noShow],
      AppointmentStatus.unknown => const [],
    };
  }
}

enum DevClinicSeedCalendarDayRelation { past, today, future }

enum DevClinicVisitDocumentationKind { none, partial, full, completedWithTreatment }
