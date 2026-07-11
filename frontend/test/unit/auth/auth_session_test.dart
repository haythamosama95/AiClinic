import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthSessionContext.needsClinicSetup', () {
    test('is true when setupRequired is true', () {
      final context = sampleAuthSessionContext(setupRequired: true);

      expect(context.needsClinicSetup, isTrue);
    });

    test('is true when organizationId is null', () {
      final context = sampleAuthSessionContext().copyWith(organizationId: null);

      expect(context.needsClinicSetup, isTrue);
    });

    test('is true when organizationId is empty or whitespace', () {
      expect(sampleAuthSessionContext().copyWith(organizationId: '').needsClinicSetup, isTrue);
      expect(sampleAuthSessionContext().copyWith(organizationId: '   ').needsClinicSetup, isTrue);
    });

    test('is false when setup is complete with a valid organization', () {
      final context = sampleAuthSessionContext(setupRequired: false);

      expect(context.needsClinicSetup, isFalse);
      expect(context.hasProperClinicSetup, isTrue);
    });

    test('copyWith recomputes needsClinicSetup when inputs change', () {
      final original = sampleAuthSessionContext(setupRequired: false);
      final cleared = original.copyWith(organizationId: null);

      expect(original.needsClinicSetup, isFalse);
      expect(cleared.needsClinicSetup, isTrue);
    });
  });
}
