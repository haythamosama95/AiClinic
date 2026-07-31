import 'package:ai_clinic/app/providers/session_context_loader.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JWT staff_role claim contract', () {
    for (final role in StaffRole.values) {
      test('parses wire value ${role.wireValue} from JWT claim fallback', () {
        expect(
          SessionContextLoader.resolveStaffRole(
            staffRowRole: null,
            claimStaffRole: role.wireValue,
          ),
          role,
        );
      });

      test('parses wire value ${role.wireValue} case-insensitively', () {
        final mixedCase = role.wireValue.split('_').map((part) {
          if (part.isEmpty) {
            return part;
          }
          return '${part[0].toUpperCase()}${part.substring(1)}';
        }).join('_');

        expect(
          SessionContextLoader.resolveStaffRole(
            staffRowRole: null,
            claimStaffRole: mixedCase,
          ),
          role,
        );
      });
    }

    test('rejects camelCase labStaff wire value', () {
      expect(
        SessionContextLoader.resolveStaffRole(
          staffRowRole: null,
          claimStaffRole: 'labStaff',
        ),
        isNull,
      );
    });

    test('prefers staff row role over JWT claim', () {
      expect(
        SessionContextLoader.resolveStaffRole(
          staffRowRole: StaffRole.doctor.wireValue,
          claimStaffRole: StaffRole.receptionist.wireValue,
        ),
        StaffRole.doctor,
      );
    });
  });
}
