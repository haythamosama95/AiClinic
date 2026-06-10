import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffRole', () {
    test('enum values exclude owner', () {
      expect(StaffRole.values, [StaffRole.administrator, StaffRole.doctor, StaffRole.receptionist, StaffRole.labStaff]);
    });

    test('tryParse rejects owner string', () {
      expect(StaffRole.tryParse('owner'), isNull);
    });

    test('tryParse accepts administrator wire values', () {
      expect(StaffRole.tryParse('administrator'), StaffRole.administrator);
      expect(StaffRole.tryParse('lab_staff'), StaffRole.labStaff);
    });

    test('administrator wireValue is administrator not owner', () {
      expect(StaffRole.administrator.wireValue, 'administrator');
    });
  });
}
