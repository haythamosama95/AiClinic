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
  /// - Today and after today: scheduled, confirmed, or cancelled only.
  static List<AppointmentStatus> allowedStatusesForCalendarDayRelation(DevClinicSeedCalendarDayRelation relation) {
    return switch (relation) {
      DevClinicSeedCalendarDayRelation.past => const [
        AppointmentStatus.completed,
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
      ],
      DevClinicSeedCalendarDayRelation.today || DevClinicSeedCalendarDayRelation.future => const [
        AppointmentStatus.scheduled,
        AppointmentStatus.confirmed,
        AppointmentStatus.cancelled,
      ],
    };
  }

  /// Primary status bucket upper bound (exclusive): buckets 0–69 → 70%.
  static const primaryStatusBucketMax = 70;

  /// Past-day no-show bucket upper bound (exclusive): buckets 70–79 → 10%.
  static const pastNoShowBucketMax = 80;

  /// Deterministic 0–99 bucket for status distribution from [seedKey].
  static int statusDistributionBucket(int seedKey) {
    final mixed = seedKey * 53 + 17;
    return ((mixed % 100) + 100) % 100;
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
<<<<<<< HEAD
    final relation = calendarDayRelationFor(
      startTimeUtc: startTimeUtc,
      timezone: timezone,
      referenceUtc: referenceUtc,
    );
=======
    final relation = calendarDayRelationFor(startTimeUtc: startTimeUtc, timezone: timezone, referenceUtc: referenceUtc);
>>>>>>> master
    final bucket = statusDistributionBucket(seedKey);

    return switch (relation) {
      DevClinicSeedCalendarDayRelation.past => switch (bucket) {
        < primaryStatusBucketMax => AppointmentStatus.completed,
        < pastNoShowBucketMax => AppointmentStatus.noShow,
        _ => AppointmentStatus.cancelled,
      },
      DevClinicSeedCalendarDayRelation.today || DevClinicSeedCalendarDayRelation.future => switch (bucket) {
        < primaryStatusBucketMax => seedKey.isEven ? AppointmentStatus.scheduled : AppointmentStatus.confirmed,
        _ => AppointmentStatus.cancelled,
      },
    };
  }

  /// Target status from [dayOffset] and [seedKey] (timezone-aware relation via [startTimeUtc]).
<<<<<<< HEAD
  static AppointmentStatus appointmentStatusForDayOffset({
    required int dayOffset,
    required int seedKey,
  }) {
=======
  static AppointmentStatus appointmentStatusForDayOffset({required int dayOffset, required int seedKey}) {
>>>>>>> master
    final relation = switch (dayOffset) {
      < 0 => DevClinicSeedCalendarDayRelation.past,
      0 => DevClinicSeedCalendarDayRelation.today,
      _ => DevClinicSeedCalendarDayRelation.future,
    };
    final bucket = statusDistributionBucket(seedKey);

    return switch (relation) {
      DevClinicSeedCalendarDayRelation.past => switch (bucket) {
        < primaryStatusBucketMax => AppointmentStatus.completed,
        < pastNoShowBucketMax => AppointmentStatus.noShow,
        _ => AppointmentStatus.cancelled,
      },
      DevClinicSeedCalendarDayRelation.today || DevClinicSeedCalendarDayRelation.future => switch (bucket) {
        < primaryStatusBucketMax => seedKey.isEven ? AppointmentStatus.scheduled : AppointmentStatus.confirmed,
        _ => AppointmentStatus.cancelled,
      },
    };
  }

  /// Deterministic appointment length in [minAppointmentDurationMinutes, maxAppointmentDurationMinutes].
  static int appointmentDurationMinutesFor(int seedKey) {
    final span = maxAppointmentDurationMinutes - minAppointmentDurationMinutes + 1;
    return minAppointmentDurationMinutes + (seedKey % span);
  }

<<<<<<< HEAD
  /// Every seeded appointment gets an assigned doctor for clear calendar and queue views.
=======
  /// Roughly half of queue-facing appointments omit a preferred doctor.
  ///
  /// Past completed appointments always keep a doctor because visit seeding requires one.
>>>>>>> master
  static bool shouldAssignDoctorForAppointment({
    required int dayOffset,
    required int patientIndex,
    required int seedKey,
    required AppointmentStatus targetStatus,
    required DevClinicSeedCalendarDayRelation dayRelation,
  }) {
<<<<<<< HEAD
    return true;
  }

  /// Deterministic doctor assignment: odd patients → branch primary doctor, even → multi-branch doctor when available.
  static String doctorIdForAppointment({
    required String primaryDoctorId,
    required String? secondaryDoctorId,
    required int patientIndex,
  }) {
    final primary = primaryDoctorId.trim();
    if (primary.isEmpty) {
      throw ArgumentError.value(primaryDoctorId, 'primaryDoctorId', 'must not be empty');
    }
=======
    if (requiresVisitAndInvoice(status: targetStatus, relation: dayRelation)) {
      return true;
    }
    return seedKey.isEven;
  }

  /// Deterministic doctor assignment: odd patients → branch primary doctor, even → multi-branch doctor when available.
  static String doctorIdForAppointment({
    required String primaryDoctorId,
    required String? secondaryDoctorId,
    required int patientIndex,
  }) {
    final primary = primaryDoctorId.trim();
    if (primary.isEmpty) {
      throw ArgumentError.value(primaryDoctorId, 'primaryDoctorId', 'must not be empty');
    }
>>>>>>> master
    final secondary = secondaryDoctorId?.trim();
    if (secondary == null || secondary.isEmpty || patientIndex.isOdd) {
      return primary;
    }
    return secondary;
  }

  /// Human-readable doctor role label for seeded appointment notes.
  static String doctorAssignmentLabel({
    required String primaryDoctorId,
    required String? secondaryDoctorId,
    required int patientIndex,
  }) {
    final assignedId = doctorIdForAppointment(
      primaryDoctorId: primaryDoctorId,
      secondaryDoctorId: secondaryDoctorId,
      patientIndex: patientIndex,
    );
    if (assignedId == primaryDoctorId.trim()) {
      return 'branch primary doctor';
    }
    return 'multi-branch doctor';
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

  /// Past completed appointments only — every one gets a visit and invoice.
  static bool requiresVisitAndInvoice({
    required AppointmentStatus status,
    required DevClinicSeedCalendarDayRelation relation,
  }) {
    return relation == DevClinicSeedCalendarDayRelation.past && status == AppointmentStatus.completed;
  }

  /// Documentation kinds cycled across completed past visits (field-combination matrix).
  static const completedVisitDocumentationKinds = <DevClinicVisitDocumentationKind>[
    DevClinicVisitDocumentationKind.partial,
    DevClinicVisitDocumentationKind.partialWithHistory,
    DevClinicVisitDocumentationKind.full,
    DevClinicVisitDocumentationKind.completedWithTreatment,
  ];

  /// Visit documentation depth for a completed past appointment.
  static DevClinicVisitDocumentationKind visitDocumentationFor({required int seedKey}) {
    return completedVisitDocumentationKinds[seedKey % completedVisitDocumentationKinds.length];
  }

  /// Whether a treatment plan should be created before completing the visit.
  static bool shouldIncludeTreatmentPlan(DevClinicVisitDocumentationKind kind) {
    return kind == DevClinicVisitDocumentationKind.completedWithTreatment;
  }

  /// Status RPC steps from `scheduled` to `in_progress` for the completed-visit path only.
  static const completedVisitAppointmentTransitions = <AppointmentStatus>[
    AppointmentStatus.confirmed,
    AppointmentStatus.checkedIn,
    AppointmentStatus.inProgress,
  ];

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
    required String doctorAssignmentLabel,
  }) {
    return 'Dev seed $branchCode patient #$patientIndex day $dayOffset — ${status.label} — $doctorAssignmentLabel.';
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
      DevClinicVisitDocumentationKind.none => (complaint: '', history: '', examination: '', diagnosis: '', plan: ''),
      DevClinicVisitDocumentationKind.partial => (
        complaint: 'Patient $label reports mild symptoms for two days.',
        history: '',
        examination: '',
        diagnosis: '',
        plan: '',
      ),
      DevClinicVisitDocumentationKind.partialWithHistory => (
        complaint: 'Patient $label reports recurring discomfort.',
        history: 'Symptoms began one week ago; no prior hospitalization.',
        examination: '',
        diagnosis: '',
        plan: '',
      ),
      DevClinicVisitDocumentationKind.partialWithHistory => (
        complaint: 'Patient $label reports recurring discomfort.',
        history: 'Symptoms began one week ago; no prior hospitalization.',
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
<<<<<<< HEAD

=======
>>>>>>> master
}

enum DevClinicSeedCalendarDayRelation { past, today, future }

enum DevClinicVisitDocumentationKind { none, partial, partialWithHistory, full, completedWithTreatment }
