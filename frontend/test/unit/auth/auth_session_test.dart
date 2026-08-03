import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffRole.wireValue', () {
    test('maps administrator to administrator', () {
      expect(StaffRole.administrator.wireValue, 'administrator');
    });

    test('maps doctor to doctor', () {
      expect(StaffRole.doctor.wireValue, 'doctor');
    });

    test('maps receptionist to receptionist', () {
      expect(StaffRole.receptionist.wireValue, 'receptionist');
    });

    test('maps labStaff to lab_staff', () {
      expect(StaffRole.labStaff.wireValue, 'lab_staff');
    });
  });

  group('StaffRole.displayLabel', () {
    test('maps administrator to Administrator', () {
      expect(StaffRole.administrator.displayLabel, 'Administrator');
    });

    test('maps doctor to Doctor', () {
      expect(StaffRole.doctor.displayLabel, 'Doctor');
    });

    test('maps receptionist to Receptionist', () {
      expect(StaffRole.receptionist.displayLabel, 'Receptionist');
    });

    test('maps labStaff to Lab staff', () {
      expect(StaffRole.labStaff.displayLabel, 'Lab staff');
    });

    test('labels are distinct and non-empty', () {
      final labels = StaffRole.values.map((role) => role.displayLabel).toList();
      expect(labels.every((label) => label.isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length);
    });
  });

  group('StaffRole.tryParse', () {
    test('round-trips every role from its wire value', () {
      for (final role in StaffRole.values) {
        expect(StaffRole.tryParse(role.wireValue), role);
      }
    });

    test('parses all wire values', () {
      for (final role in StaffRole.values) {
        expect(StaffRole.tryParse(role.wireValue), role);
      }
    });

    test('returns null for null input', () {
      expect(StaffRole.tryParse(null), isNull);
    });

    test('returns null for empty string', () {
      expect(StaffRole.tryParse(''), isNull);
    });

    test('returns null for whitespace-only input', () {
      expect(StaffRole.tryParse('   '), isNull);
    });

    test('parses padded wire values', () {
      expect(StaffRole.tryParse('  doctor  '), StaffRole.doctor);
    });

    test('parses uppercase wire values', () {
      expect(StaffRole.tryParse('DOCTOR'), StaffRole.doctor);
    });

    test('parses mixed-case wire values', () {
      expect(StaffRole.tryParse('Lab_Staff'), StaffRole.labStaff);
    });

    test('rejects camelCase labStaff wire value', () {
      expect(StaffRole.tryParse('labStaff'), isNull);
    });

    test('returns null for unknown role', () {
      expect(StaffRole.tryParse('superadmin'), isNull);
    });

    test('returns null for prefix of a valid wire value', () {
      expect(StaffRole.tryParse('doc'), isNull);
    });

    test('returns null for superset of a valid wire value', () {
      expect(StaffRole.tryParse('doctorx'), isNull);
    });
  });

  group('StaffProfile', () {
    test('exposes constructor fields for each role', () {
      for (final role in StaffRole.values) {
        final profile = StaffProfile(
          staffMemberId: 'staff-$role',
          fullName: 'Name $role',
          role: role,
          isBootstrapAdmin: false,
          isActive: true,
        );

        expect(profile.staffMemberId, 'staff-$role');
        expect(profile.fullName, 'Name $role');
        expect(profile.role, role);
        expect(profile.isBootstrapAdmin, isFalse);
        expect(profile.isActive, isTrue);
      }
    });

    test('supports inactive staff members', () {
      const profile = StaffProfile(
        staffMemberId: 'inactive',
        fullName: 'Inactive Staff',
        role: StaffRole.receptionist,
        isBootstrapAdmin: false,
        isActive: false,
      );

      expect(profile.isActive, isFalse);
    });

    test('supports bootstrap admin flag', () {
      const profile = StaffProfile(
        staffMemberId: 'bootstrap',
        fullName: 'Bootstrap Admin',
        role: StaffRole.administrator,
        isBootstrapAdmin: true,
        isActive: true,
      );

      expect(profile.isBootstrapAdmin, isTrue);
    });
  });

  group('AuthSessionContext constructor defaults', () {
    test('defaults organizationTimezone to null when omitted', () {
      final context = AuthSessionContext(
        staffProfile: const StaffProfile(
          staffMemberId: 'staff',
          fullName: 'Staff',
          role: StaffRole.administrator,
          isBootstrapAdmin: false,
          isActive: true,
        ),
        organizationId: 'org',
        branchIds: const ['branch'],
        activeBranchId: 'branch',
        permissions: const {'patients.view'},
        setupRequired: false,
      );

      expect(context.organizationTimezone, isNull);
    });
  });

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

  group('AuthSessionContext.hasProperClinicSetup', () {
    test('is the inverse of needsClinicSetup across setup permutations', () {
      final permutations = <AuthSessionContext>[
        sampleAuthSessionContext(setupRequired: true),
        sampleAuthSessionContext(setupRequired: false),
        sampleAuthSessionContext(setupRequired: false).copyWith(organizationId: null),
        sampleAuthSessionContext(setupRequired: false).copyWith(organizationId: ''),
        sampleAuthSessionContext(setupRequired: false).copyWith(organizationId: '   '),
        sampleAuthSessionContext(setupRequired: true).copyWith(
          organizationId: '00000000-0000-4000-8000-000000000099',
        ),
      ];

      for (final context in permutations) {
        expect(context.hasProperClinicSetup, !context.needsClinicSetup);
      }
    });
  });

  group('AuthSessionContext.canPerformBootstrapSetup', () {
    test('is true only for bootstrap administrator accounts', () {
      expect(
        sampleAuthSessionContext(
          role: StaffRole.administrator,
          isBootstrapAdmin: true,
        ).canPerformBootstrapSetup,
        isTrue,
      );
    });

    test('is false for non-bootstrap administrators', () {
      expect(
        sampleAuthSessionContext(
          role: StaffRole.administrator,
          isBootstrapAdmin: false,
        ).canPerformBootstrapSetup,
        isFalse,
      );
    });

    test('is false for bootstrap non-administrator roles', () {
      for (final role in StaffRole.values.where((value) => value != StaffRole.administrator)) {
        expect(
          sampleAuthSessionContext(
            role: role,
            isBootstrapAdmin: true,
          ).canPerformBootstrapSetup,
          isFalse,
          reason: role.name,
        );
      }
    });

    test('is false for regular non-bootstrap non-administrator roles', () {
      for (final role in StaffRole.values.where((value) => value != StaffRole.administrator)) {
        expect(
          sampleAuthSessionContext(
            role: role,
            isBootstrapAdmin: false,
          ).canPerformBootstrapSetup,
          isFalse,
          reason: role.name,
        );
      }
    });
  });

  group('AuthSessionContext', () {
    test('hasBranchAssignment reflects branchIds', () {
      expect(sampleAuthSessionContext(branchIds: []).hasBranchAssignment, isFalse);
      expect(sampleAuthSessionContext(branchIds: ['x']).hasBranchAssignment, isTrue);
    });

    test('copyWith updates activeBranchId only', () {
      const branchA = '00000000-0000-4000-8000-000000000001';
      const branchB = '00000000-0000-4000-8000-000000000002';
      final original = sampleAuthSessionContext(branchIds: [branchA, branchB]);
      final updated = original.copyWith(activeBranchId: branchB);

      expect(updated.activeBranchId, branchB);
      expect(updated.staffProfile, original.staffProfile);
      expect(updated.branchIds, original.branchIds);
    });

    test('copyWith with no arguments returns an equivalent context', () {
      final original = sampleAuthSessionContext(
        setupRequired: false,
        permissions: const {'patients.view', 'ai.access'},
        branchIds: const ['00000000-0000-4000-8000-000000000001'],
      ).copyWith(organizationTimezone: 'Asia/Riyadh');

      final copied = original.copyWith();

      expect(copied.staffProfile, original.staffProfile);
      expect(copied.organizationId, original.organizationId);
      expect(copied.branchIds, original.branchIds);
      expect(copied.activeBranchId, original.activeBranchId);
      expect(copied.permissions, original.permissions);
      expect(copied.setupRequired, original.setupRequired);
      expect(copied.organizationTimezone, original.organizationTimezone);
      expect(copied.needsClinicSetup, original.needsClinicSetup);
    });

    test('copyWith clearing organizationId flips needsClinicSetup to true', () {
      final original = sampleAuthSessionContext(setupRequired: false);
      final cleared = original.copyWith(organizationId: null);

      expect(cleared.organizationId, isNull);
      expect(cleared.needsClinicSetup, isTrue);
    });

    test('copyWith setting a valid organization with setupRequired false flips needsClinicSetup to false', () {
      final original = sampleAuthSessionContext(setupRequired: true);
      final ready = original.copyWith(
        organizationId: '00000000-0000-4000-8000-000000000099',
        setupRequired: false,
      );

      expect(ready.needsClinicSetup, isFalse);
    });

    test('copyWith replacing branchIds with an empty list clears branch assignment', () {
      final original = sampleAuthSessionContext(branchIds: ['branch']);
      final cleared = original.copyWith(branchIds: []);

      expect(cleared.branchIds, isEmpty);
      expect(cleared.hasBranchAssignment, isFalse);
    });

    test('copyWith replacing permissions with an empty set clears grants', () {
      final original = sampleAuthSessionContext(permissions: const {'patients.view'});
      final cleared = original.copyWith(permissions: {});

      expect(cleared.permissions, isEmpty);
    });
  });

  group('AuthSessionContext.copyWith sentinel semantics', () {
    test('omitting organizationId preserves existing value including null', () {
      final withOrg = sampleAuthSessionContext(setupRequired: false);
      final withoutOrg = sampleAuthSessionContext(setupRequired: true).copyWith(organizationId: null);

      expect(withOrg.copyWith().organizationId, withOrg.organizationId);
      expect(withoutOrg.copyWith().organizationId, isNull);
    });

    test('passing explicit null to organizationId clears it', () {
      final original = sampleAuthSessionContext(setupRequired: false);
      expect(original.copyWith(organizationId: null).organizationId, isNull);
    });

    test('omitting activeBranchId preserves existing value including null', () {
      final withBranch = sampleAuthSessionContext(branchIds: ['branch']);
      final withoutBranch = sampleAuthSessionContext(branchIds: []).copyWith(activeBranchId: null);

      expect(withBranch.copyWith().activeBranchId, withBranch.activeBranchId);
      expect(withoutBranch.copyWith().activeBranchId, isNull);
    });

    test('passing explicit null to activeBranchId clears it', () {
      final original = sampleAuthSessionContext(branchIds: ['branch']);
      expect(original.copyWith(activeBranchId: null).activeBranchId, isNull);
    });

    test('omitting organizationTimezone preserves existing value including null', () {
      final withTimezone = sampleAuthSessionContext().copyWith(organizationTimezone: 'UTC');
      final withoutTimezone = sampleAuthSessionContext();

      expect(withTimezone.copyWith().organizationTimezone, 'UTC');
      expect(withoutTimezone.copyWith().organizationTimezone, isNull);
    });

    test('passing explicit null to organizationTimezone clears it', () {
      final original = sampleAuthSessionContext().copyWith(organizationTimezone: 'UTC');
      expect(original.copyWith(organizationTimezone: null).organizationTimezone, isNull);
    });
  });

  group('AuthSessionState.isAuthenticated invariant', () {
    // Pins the load-bearing invariant that `isAuthenticated == true` implies
    // `context != null`, relied on by AuthRouteGuard (review §4.1). If anyone
    // ever relaxes this, the null-safe route-guard derefs must be revisited.
    test('is false for unknown status with null context', () {
      expect(AuthSessionState.initial().isAuthenticated, isFalse);
    });

    test('is false for loading status with null context', () {
      const state = AuthSessionState(status: AuthSessionStatus.loading);
      expect(state.isAuthenticated, isFalse);
    });

    test('is false for unauthenticated status', () {
      const state = AuthSessionState(status: AuthSessionStatus.unauthenticated);
      expect(state.isAuthenticated, isFalse);
    });

    test('is true only when status is authenticated and context is non-null', () {
      final state = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: false),
      );
      expect(state.isAuthenticated, isTrue);
      expect(state.context, isNotNull);
    });

    test('is false when status is authenticated but context is null', () {
      const state = AuthSessionState(status: AuthSessionStatus.authenticated);
      expect(state.isAuthenticated, isFalse);
    });

    test('copyWith preserves the invariant when clearing context', () {
      final authed = AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: false),
      );
      final cleared = authed.copyWith(clearContext: true);
      expect(cleared.isAuthenticated, isFalse);
    });
  });
}
