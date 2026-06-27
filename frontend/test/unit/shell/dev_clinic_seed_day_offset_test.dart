import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_schedule.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('each day offset maps to a distinct local calendar day', () {
    ensureAppointmentTimezonesInitialized();
    final referenceUtc = DateTime.utc(2026, 6, 27, 12);
    final location = tz.getLocation('Africa/Cairo');
    final localDays = <String>{};

    for (final dayOffset in DevClinicSeedSchedule.appointmentDayOffsets) {
      final start = DevClinicSeedSchedule.appointmentStartUtc(
        timezone: 'Africa/Cairo',
        dayOffset: dayOffset,
        patientIndex: 1,
        hasSecondaryDoctor: true,
        referenceUtc: referenceUtc,
      );
      final local = tz.TZDateTime.from(start, location);
      localDays.add('${local.year}-${local.month}-${local.day}');
    }

    expect(localDays.length, DevClinicSeedSchedule.appointmentDayOffsets.length);
  });
}
