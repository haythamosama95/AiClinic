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

    test('today includes every appointment status while future days stay pre-visit', () {
      final todayStatuses = <AppointmentStatus>{};
      for (var seedKey = 0; seedKey < 20; seedKey++) {
        todayStatuses.add(DevClinicSeedSchedule.appointmentStatusFor(dayOffset: 0, seedKey: seedKey));
      }
      expect(todayStatuses, containsAll(DevClinicSeedSchedule.seedableAppointmentStatuses));

      for (final dayOffset in [1, 2, 3, 4, 5]) {
        final allowed = DevClinicSeedSchedule.allowedStatusesForDayOffset(dayOffset);
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
        DevClinicVisitDocumentationKind.fullSoap,
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
      final lastEndLocal = lastLocal.add(const Duration(minutes: DevClinicSeedSchedule.appointmentDurationMinutes));

      expect(firstLocal.hour, 9);
      expect(firstLocal.minute, 0);
      expect(lastEndLocal.hour, lessThanOrEqualTo(DevClinicSeedSchedule.branchCloseLocalHour));
      if (lastEndLocal.hour == DevClinicSeedSchedule.branchCloseLocalHour) {
        expect(lastEndLocal.minute, 0);
      }
    });
  });
}
