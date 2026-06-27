import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('seed schedule fits branch hours for today', () {
    ensureAppointmentTimezonesInitialized();
    final referenceUtc = DateTime.now().toUtc();
    final location = tz.getLocation('Africa/Cairo');

    for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
      for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
        expect(
          () => DevClinicSeedSchedule.appointmentStartUtc(
            timezone: 'Africa/Cairo',
            dayOffset: dayOffset,
            patientIndex: patientIndex,
            hasSecondaryDoctor: true,
            referenceUtc: referenceUtc,
          ),
          returnsNormally,
          reason: 'dayOffset=$dayOffset patientIndex=$patientIndex reference=$referenceUtc',
        );

        final start = DevClinicSeedSchedule.appointmentStartUtc(
          timezone: 'Africa/Cairo',
          dayOffset: dayOffset,
          patientIndex: patientIndex,
          hasSecondaryDoctor: true,
          referenceUtc: referenceUtc,
        );
        final duration = DevClinicSeedSchedule.appointmentDurationMinutesFor(patientIndex + dayOffset);
        final endLocal = tz.TZDateTime.from(start, location).add(Duration(minutes: duration));
        expect(endLocal.hour, lessThanOrEqualTo(DevClinicSeedSchedule.branchCloseLocalHour));
      }
    }
  });
}
