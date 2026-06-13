import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:timezone/timezone.dart' as tz;

/// Appointment and visit scheduling helpers for dev clinic seeding.
abstract final class DevClinicSeedSchedule {
  static const appointmentDayOffsets = [-2, -1, 0, 1, 2, 3, 4, 5];
  static const appointmentDurationMinutes = 10;
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

  static List<AppointmentStatus> allowedStatusesForDayOffset(int dayOffset) {
    if (dayOffset < 0) {
      return const [AppointmentStatus.completed, AppointmentStatus.cancelled, AppointmentStatus.noShow];
    }
    if (dayOffset == 0) {
      return seedableAppointmentStatuses;
    }
    return const [AppointmentStatus.scheduled, AppointmentStatus.confirmed, AppointmentStatus.cancelled];
  }

  static AppointmentStatus appointmentStatusFor({required int dayOffset, required int seedKey}) {
    final allowed = allowedStatusesForDayOffset(dayOffset);
    return allowed[seedKey % allowed.length];
  }

  /// Whether a visit row should be created for the target appointment status.
  static bool shouldSeedVisit(AppointmentStatus status) {
    return switch (status) {
      AppointmentStatus.checkedIn || AppointmentStatus.inProgress || AppointmentStatus.completed => true,
      _ => false,
    };
  }

  /// Whether the seeded visit should be completed (requires full SOAP + treatment plan).
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

    return switch (seedKey % 3) {
      0 => DevClinicVisitDocumentationKind.partialSoap,
      1 => DevClinicVisitDocumentationKind.fullSoap,
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
    final slotIndex = patientIndex - 1;
    final startMinutes = firstSlotLocalHour * 60 + firstSlotLocalMinute + slotIndex * appointmentDurationMinutes;
    final endMinutes = startMinutes + appointmentDurationMinutes;
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

  static ({String subjective, String objective, String assessment, String plan, Map<String, dynamic> specialtyFormJson})
  soapContentFor({
    required DevClinicVisitDocumentationKind kind,
    required String branchCode,
    required int patientIndex,
    required int dayOffset,
  }) {
    final label = '$branchCode #$patientIndex day $dayOffset';
    return switch (kind) {
      DevClinicVisitDocumentationKind.none => (
        subjective: '',
        objective: '',
        assessment: '',
        plan: '',
        specialtyFormJson: const {},
      ),
      DevClinicVisitDocumentationKind.partialSoap => (
        subjective: 'Patient $label reports mild symptoms for two days.',
        objective: '',
        assessment: '',
        plan: '',
        specialtyFormJson: const {},
      ),
      DevClinicVisitDocumentationKind.fullSoap => (
        subjective: 'Patient $label reports intermittent discomfort.',
        objective: 'Vitals stable. No acute distress.',
        assessment: 'Likely viral upper respiratory infection.',
        plan: 'Hydration, rest, return if symptoms worsen.',
        specialtyFormJson: const {},
      ),
      DevClinicVisitDocumentationKind.completedWithTreatment => (
        subjective: 'Patient $label completed follow-up visit.',
        objective: 'Exam unremarkable. Labs reviewed.',
        assessment: 'Condition improving on current regimen.',
        plan: 'Continue medication, schedule routine follow-up.',
        specialtyFormJson: const {},
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

enum DevClinicVisitDocumentationKind { none, partialSoap, fullSoap, completedWithTreatment }
