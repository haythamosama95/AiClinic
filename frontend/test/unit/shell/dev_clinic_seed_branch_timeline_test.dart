import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dev seed uses a single sequential branch-day timeline ([hasSecondaryDoctor: false])
/// so dummy data fills successfully whether overlap is per-doctor or branch-wide.
void main() {
  test('sequential branch timeline has no overlaps in seed creation order', () {
    final referenceUtc = DateTime.now().toUtc();
    final active = <(DateTime start, DateTime end)>[];

    for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
      for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
        final seedKey = patientIndex + dayOffset;
        final targetStatus = DevClinicSeedSchedule.appointmentStatusFor(dayOffset: dayOffset, seedKey: seedKey);
        final start = DevClinicSeedSchedule.appointmentStartUtc(
          timezone: DevClinicSeedSpec.timezone,
          dayOffset: dayOffset,
          patientIndex: patientIndex,
          hasSecondaryDoctor: false,
          referenceUtc: referenceUtc,
        );
        final duration = DevClinicSeedSchedule.appointmentDurationMinutesFor(seedKey);
        final end = start.add(Duration(minutes: duration));

        for (final existing in active) {
          final overlaps = start.isBefore(existing.$2) && end.isAfter(existing.$1);
          expect(
            overlaps,
            isFalse,
            reason: 'patient=$patientIndex day=$dayOffset conflicts with ${existing.$1}–${existing.$2}',
          );
        }

        if (targetStatus != AppointmentStatus.cancelled && targetStatus != AppointmentStatus.noShow) {
          active.add((start, end));
        }
      }
    }
  });
}
