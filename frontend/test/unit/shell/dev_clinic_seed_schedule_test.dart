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

    test('visit clinical note seed data includes all five sections when full', () {
      final note = DevClinicSeedSchedule.clinicalNoteContentFor(
        kind: DevClinicVisitDocumentationKind.full,
        branchCode: 'DTWN',
        patientIndex: 1,
        dayOffset: 0,
      );
      expect(note.complaint, isNotEmpty);
      expect(note.history, isNotEmpty);
      expect(note.examination, isNotEmpty);
      expect(note.diagnosis, isNotEmpty);
      expect(note.plan, isNotEmpty);
    });

    test('status distribution uses exact bucket boundaries', () {
      expect(DevClinicSeedSchedule.statusDistributionBucket(0), inInclusiveRange(0, 99));

      // Past: 0-69 completed, 70-79 no_show, 80-99 cancelled
      for (var bucket = 0; bucket < 70; bucket++) {
        expect(
          DevClinicSeedSchedule.appointmentStatusForDayOffset(dayOffset: -1, seedKey: _seedKeyForBucket(bucket)),
          AppointmentStatus.completed,
        );
      }
      for (var bucket = 70; bucket < 80; bucket++) {
        expect(
          DevClinicSeedSchedule.appointmentStatusForDayOffset(dayOffset: -1, seedKey: _seedKeyForBucket(bucket)),
          AppointmentStatus.noShow,
        );
      }
      for (var bucket = 80; bucket < 100; bucket++) {
        expect(
          DevClinicSeedSchedule.appointmentStatusForDayOffset(dayOffset: -1, seedKey: _seedKeyForBucket(bucket)),
          AppointmentStatus.cancelled,
        );
      }

      // Today/future: 0-69 scheduled/confirmed, 70-99 cancelled
      for (var bucket = 0; bucket < 70; bucket++) {
        final seedKey = _seedKeyForBucket(bucket);
        final status = DevClinicSeedSchedule.appointmentStatusForDayOffset(dayOffset: 0, seedKey: seedKey);
        expect(status, seedKey.isEven ? AppointmentStatus.scheduled : AppointmentStatus.confirmed);
      }
      for (var bucket = 70; bucket < 100; bucket++) {
        expect(
          DevClinicSeedSchedule.appointmentStatusForDayOffset(dayOffset: 1, seedKey: _seedKeyForBucket(bucket)),
          AppointmentStatus.cancelled,
        );
      }
    });

    test('appointment statuses follow calendar-day rules across seeded patients', () {
      const timezone = 'Africa/Cairo';
      final referenceUtc = DateTime.utc(2026, 6, 13, 12);

      final pastStatuses = <AppointmentStatus>[];
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
      expect(pastStatuses.toSet(), {AppointmentStatus.completed, AppointmentStatus.cancelled, AppointmentStatus.noShow});
      expect(pastStatuses.where((status) => status == AppointmentStatus.completed).length, 22);
      expect(pastStatuses.where((status) => status == AppointmentStatus.noShow).length, 4);
      expect(pastStatuses.where((status) => status == AppointmentStatus.cancelled).length, 6);

      final todayAndFutureStatuses = <AppointmentStatus>[];
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        for (final dayOffset in [0, 1, 2, 3, 4, 5]) {
          final seedKey = patientIndex + dayOffset;
          final startTime = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: timezone,
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );
          todayAndFutureStatuses.add(
            DevClinicSeedSchedule.appointmentStatusFor(
              startTimeUtc: startTime,
              timezone: timezone,
              seedKey: seedKey,
              referenceUtc: referenceUtc,
            ),
          );
        }
      }
      expect(
        todayAndFutureStatuses.toSet(),
        {AppointmentStatus.scheduled, AppointmentStatus.confirmed, AppointmentStatus.cancelled},
      );
      expect(
        todayAndFutureStatuses.where((status) => status == AppointmentStatus.cancelled).length,
        27,
      );
      expect(
        todayAndFutureStatuses
            .where((status) => status == AppointmentStatus.scheduled || status == AppointmentStatus.confirmed)
            .length,
        69,
      );

      for (final dayOffset in [0, 1, 2, 3, 4, 5]) {
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

    test('visit and invoice are required only for past completed appointments', () {
      expect(
        DevClinicSeedSchedule.requiresVisitAndInvoice(
          status: AppointmentStatus.completed,
          relation: DevClinicSeedCalendarDayRelation.past,
        ),
        isTrue,
      );
      expect(
        DevClinicSeedSchedule.requiresVisitAndInvoice(
          status: AppointmentStatus.completed,
          relation: DevClinicSeedCalendarDayRelation.today,
        ),
        isFalse,
      );
      expect(
        DevClinicSeedSchedule.requiresVisitAndInvoice(
          status: AppointmentStatus.noShow,
          relation: DevClinicSeedCalendarDayRelation.past,
        ),
        isFalse,
      );
      expect(
        DevClinicSeedSchedule.requiresVisitAndInvoice(
          status: AppointmentStatus.cancelled,
          relation: DevClinicSeedCalendarDayRelation.past,
        ),
        isFalse,
      );
      expect(
        DevClinicSeedSchedule.requiresVisitAndInvoice(
          status: AppointmentStatus.scheduled,
          relation: DevClinicSeedCalendarDayRelation.future,
        ),
        isFalse,
      );
    });

    test('completed visits cycle through documentation field combinations', () {
      final kinds = <DevClinicVisitDocumentationKind>{};
      for (var seedKey = 0; seedKey < 20; seedKey++) {
        kinds.add(DevClinicSeedSchedule.visitDocumentationFor(seedKey: seedKey));
      }
      expect(kinds, DevClinicSeedSchedule.completedVisitDocumentationKinds.toSet());

      final partial = DevClinicSeedSchedule.clinicalNoteContentFor(
        kind: DevClinicVisitDocumentationKind.partial,
        branchCode: 'DTWN',
        patientIndex: 1,
        dayOffset: -1,
      );
      expect(partial.complaint, isNotEmpty);
      expect(partial.history, isEmpty);

      final partialHistory = DevClinicSeedSchedule.clinicalNoteContentFor(
        kind: DevClinicVisitDocumentationKind.partialWithHistory,
        branchCode: 'DTWN',
        patientIndex: 1,
        dayOffset: -1,
      );
      expect(partialHistory.complaint, isNotEmpty);
      expect(partialHistory.history, isNotEmpty);
      expect(partialHistory.examination, isEmpty);

      expect(
        DevClinicSeedSchedule.shouldIncludeTreatmentPlan(DevClinicVisitDocumentationKind.completedWithTreatment),
        isTrue,
      );
      expect(DevClinicSeedSchedule.shouldIncludeTreatmentPlan(DevClinicVisitDocumentationKind.full), isFalse);
    });

    test('completed visit path uses only the minimal in-progress transitions', () {
      expect(
        DevClinicSeedSchedule.completedVisitAppointmentTransitions,
        const [
          AppointmentStatus.confirmed,
          AppointmentStatus.checkedIn,
          AppointmentStatus.inProgress,
        ],
      );
      expect(
        DevClinicSeedSchedule.completedVisitAppointmentTransitions,
        isNot(contains(AppointmentStatus.completed)),
      );
    });

    test('appointment durations range from 30 to 90 minutes', () {
      for (var seedKey = 0; seedKey < 200; seedKey++) {
        final duration = DevClinicSeedSchedule.appointmentDurationMinutesFor(seedKey);
        expect(duration, inInclusiveRange(30, 90));
      }
    });

    test('every seeded appointment is assigned a doctor', () {
      for (var seedKey = 0; seedKey < 60; seedKey++) {
        expect(
          DevClinicSeedSchedule.shouldAssignDoctorForAppointment(dayOffset: 1, patientIndex: 1, seedKey: seedKey),
          isTrue,
        );
      }
    });

    test('doctor assignment alternates branch primary and multi-branch doctors', () {
      expect(
        DevClinicSeedSchedule.doctorIdForAppointment(
          primaryDoctorId: 'branch-doc',
          secondaryDoctorId: 'multi-doc',
          patientIndex: 1,
        ),
        'branch-doc',
      );
      expect(
        DevClinicSeedSchedule.doctorIdForAppointment(
          primaryDoctorId: 'branch-doc',
          secondaryDoctorId: 'multi-doc',
          patientIndex: 2,
        ),
        'multi-doc',
      );
      expect(
        DevClinicSeedSchedule.doctorAssignmentLabel(
          primaryDoctorId: 'branch-doc',
          secondaryDoctorId: 'multi-doc',
          patientIndex: 2,
        ),
        'multi-branch doctor',
      );
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

    test('today and future targets never require visit path transitions', () {
      const timezone = 'Africa/Cairo';
      final referenceUtc = DateTime.utc(2026, 7, 17, 10);

      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        for (final dayOffset in [0, 1, 2]) {
          final startTime = DevClinicSeedSchedule.appointmentStartUtc(
            timezone: timezone,
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            referenceUtc: referenceUtc,
          );
          final relation = DevClinicSeedSchedule.calendarDayRelationFor(
            startTimeUtc: startTime,
            timezone: timezone,
            referenceUtc: referenceUtc,
          );
          final target = DevClinicSeedSchedule.appointmentStatusFor(
            startTimeUtc: startTime,
            timezone: timezone,
            seedKey: patientIndex + dayOffset,
            referenceUtc: referenceUtc,
          );

          expect(
            DevClinicSeedSchedule.requiresVisitAndInvoice(status: target, relation: relation),
            isFalse,
          );
          expect(target, isNot(AppointmentStatus.checkedIn));
          expect(target, isNot(AppointmentStatus.inProgress));
          expect(target, isNot(AppointmentStatus.completed));
        }
      }
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

/// Finds a seed key whose [DevClinicSeedSchedule.statusDistributionBucket] equals [bucket].
int _seedKeyForBucket(int bucket) {
  for (var seedKey = 0; seedKey < 500; seedKey++) {
    if (DevClinicSeedSchedule.statusDistributionBucket(seedKey) == bucket) {
      return seedKey;
    }
  }
  throw StateError('No seed key found for bucket $bucket');
}
