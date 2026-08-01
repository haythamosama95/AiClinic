import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalStatus', () {
    test('tryParse accepts active and inactive', () {
      expect(GlobalStatus.tryParse('active'), GlobalStatus.active);
      expect(GlobalStatus.tryParse('INACTIVE'), GlobalStatus.inactive);
      expect(GlobalStatus.tryParse(' inactive '), GlobalStatus.inactive);
    });

    test('tryParse returns null for unknown or empty values', () {
      expect(GlobalStatus.tryParse(null), isNull);
      expect(GlobalStatus.tryParse(''), isNull);
      expect(GlobalStatus.tryParse('deleted'), isNull);
    });

    test('wireValue matches enum name', () {
      expect(GlobalStatus.active.wireValue, 'active');
      expect(GlobalStatus.inactive.wireValue, 'inactive');
    });
  });
}
