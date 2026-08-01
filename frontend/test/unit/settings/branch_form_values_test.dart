import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/branch_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

BranchFormValues _validBranchFormValues() {
  return BranchFormValues(
    name: 'Main Branch',
    code: 'MAIN',
    address: '123 Street',
    phone: '1234567890',
    mapsUrl: 'https://maps.example.com',
    workingSchedule: defaultWorkingSchedule(),
  );
}

void main() {
  group('emptyBranchFormValues', () {
    test('returns empty strings and empty working schedule', () {
      final values = emptyBranchFormValues();

      expect(values.name, '');
      expect(values.code, '');
      expect(values.address, '');
      expect(values.phone, '');
      expect(values.mapsUrl, '');
      expect(values.workingSchedule, emptyWorkingSchedule());
      expect(hasConfiguredWorkingHours(values.workingSchedule), isFalse);
    });
  });

  group('branchToFormValues', () {
    test('maps branch fields and substitutes null optionals with empty strings', () {
      const branch = BranchListItem(
        id: 'branch-1',
        name: 'Downtown',
        isActive: true,
        code: 'DT',
        address: 'Street 1',
        phone: '5551234',
        mapsUrl: 'https://maps.test',
        workingSchedule: null,
      );

      final values = branchToFormValues(branch);

      expect(values.name, 'Downtown');
      expect(values.code, 'DT');
      expect(values.address, 'Street 1');
      expect(values.phone, '5551234');
      expect(values.mapsUrl, 'https://maps.test');
      expect(values.workingSchedule, emptyWorkingSchedule());
    });

    test('preserves configured working schedule from branch', () {
      final schedule = defaultWorkingSchedule();
      final branch = BranchListItem(
        id: 'branch-1',
        name: 'Downtown',
        isActive: true,
        workingSchedule: schedule,
      );

      expect(branchToFormValues(branch).workingSchedule, schedule);
    });
  });

  group('validateBranch', () {
    test('returns no errors for valid values when hours are required', () {
      final errors = validateBranch(_validBranchFormValues(), requireHours: true);

      expect(errors, isEmpty);
    });

    test('requires branch name', () {
      final values = _validBranchFormValues().copyWith(name: '   ');

      final errors = validateBranch(values, requireHours: false);

      expect(errors['name'], 'Branch name is required');
    });

    test('requires working hours on create', () {
      final values = _validBranchFormValues().copyWith(workingSchedule: emptyWorkingSchedule());

      final errors = validateBranch(values, requireHours: true);

      expect(errors['workingSchedule'], 'Working hours are required');
    });

    test('skips working hours validation when requireHours is false', () {
      final values = _validBranchFormValues().copyWith(workingSchedule: emptyWorkingSchedule());

      final errors = validateBranch(values, requireHours: false);

      expect(errors.containsKey('workingSchedule'), isFalse);
    });

    test('reports required code, address, phone, and maps URL', () {
      final values = emptyBranchFormValues();

      final errors = validateBranch(values, requireHours: false);

      expect(errors['code'], 'Branch code is required');
      expect(errors['address'], 'Address is required');
      expect(errors['phone'], 'Phone is required');
      expect(errors['mapsUrl'], 'Maps URL is required');
    });

    test('rejects non-numeric phone and invalid maps URL', () {
      final values = _validBranchFormValues().copyWith(
        phone: 'abc',
        mapsUrl: 'http:',
      );

      final errors = validateBranch(values, requireHours: false);

      expect(errors['phone'], 'Phone must contain numbers only');
      expect(errors['mapsUrl'], 'Enter a valid URL');
    });

    test('accepts maps URL without scheme by normalizing to https', () {
      final values = _validBranchFormValues().copyWith(mapsUrl: 'maps.example.com/place');

      final errors = validateBranch(values, requireHours: false);

      expect(errors.containsKey('mapsUrl'), isFalse);
    });
  });

  group('createBranchInputFromFormValues', () {
    test('trims text fields and keeps configured working schedule', () {
      final values = _validBranchFormValues().copyWith(
        name: '  Main  ',
        phone: ' 1234567890 ',
        mapsUrl: ' https://maps.example.com ',
      );

      final input = createBranchInputFromFormValues(values);

      expect(input.name, 'Main');
      expect(input.code, 'MAIN');
      expect(input.address, '123 Street');
      expect(input.phone, '1234567890');
      expect(input.mapsUrl, 'https://maps.example.com');
      expect(input.workingSchedule, values.workingSchedule);
    });
  });

  group('updateBranchInputFromFormValues', () {
    test('maps branch id and trimmed form values', () {
      final values = _validBranchFormValues().copyWith(name: '  Updated  ');

      final input = updateBranchInputFromFormValues(branchId: 'branch-42', values: values);

      expect(input.branchId, 'branch-42');
      expect(input.name, 'Updated');
      expect(input.workingSchedule, values.workingSchedule);
    });
  });
}
