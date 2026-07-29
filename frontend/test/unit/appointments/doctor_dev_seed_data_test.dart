import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoctorDevSeedData', () {
    test('trivial: doctors seed list is non-empty', () {
      expect(DoctorDevSeedData.doctors, isNotEmpty);
    });

    test('advanced: seed usernames are unique', () {
      final usernames = DoctorDevSeedData.doctors.map((doctor) => doctor.username).toList();
      expect(usernames.toSet().length, usernames.length);
    });

    test('regression: every seeded fullName uses the dev detection prefix', () {
      for (final doctor in DoctorDevSeedData.doctors) {
        expect(doctor.fullName.startsWith(DoctorDevSeedSpec.devNamePrefix), isTrue);
      }
    });

    test('trivial: defaultPassword is non-empty', () {
      expect(DoctorDevSeedData.defaultPassword.trim(), isNotEmpty);
    });
  });
}
