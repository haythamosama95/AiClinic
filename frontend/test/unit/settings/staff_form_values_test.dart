import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';
import 'package:flutter_test/flutter_test.dart';

StaffFormValues _validCreateStaffFormValues() {
  return const StaffFormValues(
    fullName: 'Jane Doe',
    phone: '1234567890',
    username: 'jane',
    password: 'Password1',
    role: StaffRole.doctor,
    branchIds: ['branch-1'],
    primaryBranchId: 'branch-1',
  );
}

void main() {
  group('emptyStaffFormValues', () {
    test('returns default empty draft', () {
      final values = emptyStaffFormValues();

      expect(values.fullName, '');
      expect(values.phone, '');
      expect(values.username, '');
      expect(values.password, '');
      expect(values.role, isNull);
      expect(values.branchIds, isEmpty);
      expect(values.primaryBranchId, isNull);
    });
  });

  group('staffToFormValues', () {
    test('maps staff fields and derives branch assignments', () {
      const staff = StaffListItem(
        id: 'staff-1',
        fullName: 'Dr. Ada',
        role: StaffRole.doctor,
        isActive: true,
        phone: '5550000',
        username: 'ada',
        branches: [
          StaffBranchLabel(id: 'branch-1', name: 'Main', isPrimary: true),
          StaffBranchLabel(id: 'branch-2', name: 'East', isPrimary: false),
        ],
      );

      final values = staffToFormValues(staff);

      expect(values.fullName, 'Dr. Ada');
      expect(values.phone, '5550000');
      expect(values.username, 'ada');
      expect(values.password, '');
      expect(values.role, StaffRole.doctor);
      expect(values.branchIds, ['branch-1', 'branch-2']);
      expect(values.primaryBranchId, 'branch-1');
    });

    test('uses sole branch as primary when no primary flag is set', () {
      const staff = StaffListItem(
        id: 'staff-1',
        fullName: 'Sam',
        role: StaffRole.receptionist,
        isActive: true,
        branches: [StaffBranchLabel(id: 'branch-1', name: 'Main')],
      );

      expect(staffToFormValues(staff).primaryBranchId, 'branch-1');
    });
  });

  group('validateStaff create mode', () {
    test('returns no errors for valid create draft', () {
      final errors = validateStaff(_validCreateStaffFormValues(), StaffFormMode.create);

      expect(errors, isEmpty);
    });

    test('requires full name, phone, username, password, role, and branches', () {
      final errors = validateStaff(emptyStaffFormValues(), StaffFormMode.create);

      expect(errors['fullName'], 'Full name is required');
      expect(errors['phone'], 'Phone is required');
      expect(errors['username'], 'Username is required');
      expect(errors['password'], 'Password is required');
      expect(errors['role'], 'Select a role');
      expect(errors['branchIds'], 'Select at least one branch assignment');
    });

    test('rejects invalid phone, username, and weak password on create', () {
      final values = _validCreateStaffFormValues().copyWith(
        phone: 'abc',
        username: '1bad',
        password: 'short',
      );

      final errors = validateStaff(values, StaffFormMode.create);

      expect(errors['phone'], 'Phone must contain numbers only');
      expect(errors['username'], 'Username format is invalid');
      expect(errors['password'], 'Password must be at least 8 characters');
    });
  });

  group('validateStaff edit mode', () {
    test('does not require phone or password when empty', () {
      final values = _validCreateStaffFormValues().copyWith(phone: '', password: '');

      final errors = validateStaff(values, StaffFormMode.edit);

      expect(errors.containsKey('phone'), isFalse);
      expect(errors.containsKey('password'), isFalse);
    });

    test('still validates phone format when provided', () {
      final values = _validCreateStaffFormValues().copyWith(phone: 'abc', password: '');

      final errors = validateStaff(values, StaffFormMode.edit);

      expect(errors['phone'], 'Phone must contain numbers only');
    });

    test('validates optional password strength when provided', () {
      final values = _validCreateStaffFormValues().copyWith(password: 'weakpass');

      final errors = validateStaff(values, StaffFormMode.edit);

      expect(errors['password'], 'Password must include an uppercase letter');
    });
  });

  group('toCreateStaffAccountInput', () {
    test('maps trimmed values and omits empty phone', () {
      final values = _validCreateStaffFormValues().copyWith(
        fullName: '  Jane Doe  ',
        username: ' jane ',
        phone: '   ',
      );

      final input = toCreateStaffAccountInput(values);

      expect(input.fullName, 'Jane Doe');
      expect(input.username, 'jane');
      expect(input.password, 'Password1');
      expect(input.role, StaffRole.doctor);
      expect(input.branchIds, ['branch-1']);
      expect(input.primaryBranchId, 'branch-1');
      expect(input.phone, isNull);
    });
  });

  group('toUpdateStaffMemberInput', () {
    test('maps staff member id and trimmed values', () {
      final values = _validCreateStaffFormValues().copyWith(fullName: '  Updated Name  ');

      final input = toUpdateStaffMemberInput('staff-99', values);

      expect(input.staffMemberId, 'staff-99');
      expect(input.fullName, 'Updated Name');
      expect(input.role, StaffRole.doctor);
      expect(input.branchIds, ['branch-1']);
      expect(input.phone, '1234567890');
    });
  });
}
