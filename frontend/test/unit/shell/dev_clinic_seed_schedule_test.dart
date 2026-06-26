import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('DevClinicSeedSchedule', () {
    test('covers eight appointment days from two days ago through five days ahead', () {
      expect(DevClinicSeedSchedule.appointmentDayOffsets, [-2, -1, 0, 1, 2, 3, 4, 5]);
    });

    test('patient demographics use backend-supported values only', () {
      final genders = {for (var i = 0; i < 8; i++) DevClinicSeedSchedule.patientGender(i)};
      expect(genders, DevClinicSeedSchedule.seedablePatientGenders.toSet());

      final maritalStatuses = {for (var i = 0; i < 8; i++) DevClinicSeedSchedule.patientMaritalStatus(i)};
      expect(maritalStatuses, PatientMaritalStatus.values.toSet());
      expect(DevClinicSeedSchedule.patientNotes(branchCode: 'DTWN', patientIndex: 1), contains('DTWN'));
    });

    test('visit SOAP seed data omits specialty form fields until org schema exists', () {
      final soap = DevClinicSeedSchedule.soapContentFor(
        kind: DevClinicVisitDocumentationKind.fullSoap,
        branchCode: 'DTWN',
        patientIndex: 1,
        dayOffset: 0,
      );
      expect(soap.specialtyFormJson, isEmpty);
    });

    test('appointment statuses follow calendar-day rules in org timezone', () {
      const timezone = 'Africa/Cairo';
      final referenceUtc = DateTime.utc(2026, 6, 13, 12);

      final pastStatuses = <AppointmentStatus>{};
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        for (final dayOffset in [-2, -1]) {
          final seedKey = patientIndex + dayOffset;
          final startTime = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: timezone,
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );
          pastStatuses.add(
            DevClinicSeedSchedule.appointmentStatusFor(
              startTimeUtc: startTime,
              timezone: timezone,
              seedKey: seedKey,
              referenceUtc: referenceUtc,
            ),
          );
        }
      }
      expect(pastStatuses, {AppointmentStatus.completed, AppointmentStatus.cancelled, AppointmentStatus.noShow});
      expect(pastStatuses, isNot(contains(AppointmentStatus.scheduled)));
      expect(pastStatuses, isNot(contains(AppointmentStatus.confirmed)));
      expect(pastStatuses, isNot(contains(AppointmentStatus.checkedIn)));
      expect(pastStatuses, isNot(contains(AppointmentStatus.inProgress)));

      final todayStatuses = <AppointmentStatus>{};
      for (var seedKey = 0; seedKey < 20; seedKey++) {
        final startTime = DevClinicSeedSchedule.appointmentStartUtc(
          timezone: timezone,
          dayOffset: 0,
          patientIndex: 1,
          referenceUtc: referenceUtc,
        );
        todayStatuses.add(
          DevClinicSeedSchedule.appointmentStatusFor(
            startTimeUtc: startTime,
            timezone: timezone,
            seedKey: seedKey,
            referenceUtc: referenceUtc,
          ),
        );
      }
      expect(todayStatuses, {AppointmentStatus.confirmed});

      for (final dayOffset in [1, 2, 3, 4, 5]) {
        final startTime = DevClinicSeedSchedule.appointmentStartUtc(
          timezone: timezone,
          dayOffset: dayOffset,
          patientIndex: 1,
          referenceUtc: referenceUtc,
        );
        final allowed = DevClinicSeedSchedule.allowedStatusesForStartTime(
          startTimeUtc: startTime,
          timezone: timezone,
          referenceUtc: referenceUtc,
        );
        expect(allowed, DevClinicSeedSchedule.allowedStatusesForDayOffset(dayOffset));
        expect(allowed, isNot(contains(AppointmentStatus.checkedIn)));
        expect(allowed, isNot(contains(AppointmentStatus.inProgress)));
        expect(allowed, isNot(contains(AppointmentStatus.completed)));
        expect(allowed, isNot(contains(AppointmentStatus.noShow)));
      }
    });

    test('visit documentation includes partial, full, and completed treatment paths', () {
      expect(
        DevClinicSeedSchedule.visitDocumentationFor(status: AppointmentStatus.checkedIn, seedKey: 0),
        DevClinicVisitDocumentationKind.partialSoap,
      );
      expect(
        DevClinicSeedSchedule.visitDocumentationFor(status: AppointmentStatus.inProgress, seedKey: 1),
        DevClinicVisitDocumentationKind.partialSoap,
      );
      expect(
        DevClinicSeedSchedule.visitDocumentationFor(status: AppointmentStatus.completed, seedKey: 2),
        DevClinicVisitDocumentationKind.completedWithTreatment,
      );
      expect(
        DevClinicSeedSchedule.visitDocumentationFor(status: AppointmentStatus.scheduled, seedKey: 0),
        DevClinicVisitDocumentationKind.none,
      );
    });

    test('appointment durations range from 30 to 90 minutes', () {
      for (var seedKey = 0; seedKey < 200; seedKey++) {
        final duration = DevClinicSeedSchedule.appointmentDurationMinutesFor(seedKey);
        expect(duration, inInclusiveRange(30, 90));
      }
    });

    test('roughly one in six non-today seeded appointments omit doctor assignment', () {
      final unassigned = <int>[];
      for (var seedKey = 0; seedKey < 60; seedKey++) {
        if (!DevClinicSeedSchedule.shouldAssignDoctorForAppointment(dayOffset: 1, patientIndex: 1, seedKey: seedKey)) {
          unassigned.add(seedKey);
        }
      }
      expect(unassigned, [0, 6, 12, 18, 24, 30, 36, 42, 48, 54]);
      expect(DevClinicSeedSchedule.shouldAssignDoctorForAppointment(dayOffset: 1, patientIndex: 1, seedKey: 1), isTrue);
    });

    test('today seeded appointments split preferred doctors evenly', () {
      final withDoctor = <int>[];
      final withoutDoctor = <int>[];
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        final assigned = DevClinicSeedSchedule.shouldAssignDoctorForAppointment(
          dayOffset: 0,
          patientIndex: patientIndex,
          seedKey: patientIndex,
        );
        if (assigned) {
          withDoctor.add(patientIndex);
        } else {
          withoutDoctor.add(patientIndex);
        }
      }
      expect(withDoctor.length, DevClinicSeedSpec.patientsPerBranch ~/ 2);
      expect(withoutDoctor.length, DevClinicSeedSpec.patientsPerBranch ~/ 2);
      expect(withDoctor, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(withoutDoctor, [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('shift seeding covers today through five days ahead only', () {
      expect(DevClinicSeedSchedule.shiftDayOffsets, [0, 1, 2, 3, 4, 5]);
    });

    test('shift doctors match appointment doctor options per branch', () {
      expect(DevClinicSeedSchedule.shiftDoctorIdsForBranch(primaryDoctorId: 'doc-a', secondaryDoctorId: null), [
        'doc-a',
      ]);
      expect(DevClinicSeedSchedule.shiftDoctorIdsForBranch(primaryDoctorId: 'doc-a', secondaryDoctorId: 'doc-b'), [
        'doc-a',
        'doc-b',
      ]);
      expect(DevClinicSeedSchedule.shiftDoctorIdsForBranch(primaryDoctorId: 'doc-a', secondaryDoctorId: 'doc-a'), [
        'doc-a',
      ]);
    });

    test('shift dates follow org timezone day offsets', () {
      final referenceUtc = DateTime.utc(2026, 6, 13, 22);
      final today = DevClinicSeedSchedule.shiftDateLocal(
        timezone: 'Africa/Cairo',
        dayOffset: 0,
        referenceUtc: referenceUtc,
      );
      final tomorrow = DevClinicSeedSchedule.shiftDateLocal(
        timezone: 'Africa/Cairo',
        dayOffset: 1,
        referenceUtc: referenceUtc,
      );

      expect(today, DateTime(2026, 6, 14));
      expect(tomorrow, DateTime(2026, 6, 15));
    });

    test('unassigned appointments avoid visit-eligible statuses', () {
      expect(
        DevClinicSeedSchedule.appointmentTargetWithoutDoctor(AppointmentStatus.checkedIn),
        AppointmentStatus.confirmed,
      );
      expect(
        DevClinicSeedSchedule.appointmentTargetWithoutDoctor(AppointmentStatus.completed),
        AppointmentStatus.confirmed,
      );
      expect(
        DevClinicSeedSchedule.appointmentTargetWithoutDoctor(AppointmentStatus.scheduled),
        AppointmentStatus.scheduled,
      );
    });

    test('appointments on the same branch day do not overlap', () {
      for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
        final referenceUtc = DateTime.utc(2026, 6, 13, 12);

        for (var patientIndex = 2; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
          final previousStart = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: 'Africa/Cairo',
            dayOffset: dayOffset,
            patientIndex: patientIndex - 1,
            referenceUtc: referenceUtc,
          );
          final currentStart = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: 'Africa/Cairo',
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );
          final previousDuration = DevClinicSeedSchedule.appointmentDurationMinutesFor(patientIndex - 1 + dayOffset);

          expect(currentStart, previousStart.add(Duration(minutes: previousDuration)));
        }
      }
    });

    test('in-progress seeded visits always include SOAP so doctor slots can be released', () {
      for (var seedKey = 0; seedKey < 12; seedKey++) {
        expect(
          DevClinicSeedSchedule.visitDocumentationFor(status: AppointmentStatus.inProgress, seedKey: seedKey),
          isNot(DevClinicVisitDocumentationKind.none),
        );
      }
    });

    test('doctor availability resolver keeps one active visit per doctor', () {
      expect(
        DevClinicSeedSchedule.resolveTargetForDoctorAvailability(
          target: AppointmentStatus.inProgress,
          seedKey: 3,
          doctorAlreadyInProgress: false,
        ),
        AppointmentStatus.inProgress,
      );
      expect(
        DevClinicSeedSchedule.resolveTargetForDoctorAvailability(
          target: AppointmentStatus.inProgress,
          seedKey: 3,
          doctorAlreadyInProgress: true,
        ),
        AppointmentStatus.confirmed,
      );
      expect(
        DevClinicSeedSchedule.resolveTargetForDoctorAvailability(
          target: AppointmentStatus.completed,
          seedKey: 3,
          doctorAlreadyInProgress: true,
        ),
        AppointmentStatus.completed,
      );
      expect(DevClinicSeedSchedule.leavesDoctorInProgress(status: AppointmentStatus.completed, seedKey: 3), isFalse);
      expect(DevClinicSeedSchedule.requiresInProgressTransition(AppointmentStatus.completed), isTrue);
    });

    test('appointment slots start at 9 AM and end by branch close at 9 PM', () {
      final first = DevClinicSeedSchedule.appointmentStartUtc(
        timezone: 'Africa/Cairo',
        dayOffset: 0,
        patientIndex: 1,
        referenceUtc: DateTime.utc(2026, 6, 13, 12),
      );
      final last = DevClinicSeedSchedule.appointmentStartUtc(
        timezone: 'Africa/Cairo',
        dayOffset: 0,
        patientIndex: DevClinicSeedSpec.patientsPerBranch,
        referenceUtc: DateTime.utc(2026, 6, 13, 12),
      );

      final location = tz.getLocation('Africa/Cairo');
      final firstLocal = tz.TZDateTime.from(first, location);
      final lastLocal = tz.TZDateTime.from(last, location);
      final lastDuration = DevClinicSeedSchedule.appointmentDurationMinutesFor(DevClinicSeedSpec.patientsPerBranch);
      final lastEndLocal = lastLocal.add(Duration(minutes: lastDuration));

      expect(firstLocal.hour, 9);
      expect(firstLocal.minute, 0);
      expect(lastEndLocal.hour, lessThanOrEqualTo(DevClinicSeedSchedule.branchCloseLocalHour));
      if (lastEndLocal.hour == DevClinicSeedSchedule.branchCloseLocalHour) {
        expect(lastEndLocal.minute, 0);
      }
    });
  });
}
