import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_validation.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_validation.dart';
import 'package:flutter_test/flutter_test.dart';

BranchDraft _branch({
  String id = 'branch-1',
  String name = 'Main',
  String code = 'MAIN',
  String mobile = '1000000000',
  String mapLocation = 'https://maps.google.com/place/test',
}) {
  return BranchDraft(
    id: id,
    name: name,
    code: code,
    mobile: mobile,
    mapLocation: mapLocation,
    workingDays: createDefaultWorkingDays(),
  );
}

StaffDraft _staff({
  String id = 'staff-1',
  String name = 'Dr. Sara Hassan',
  String mobile = '1000000001',
  String username = 'sara_hassan',
  String password = 'Secret12',
  String role = 'doctor',
  List<String> branchIds = const ['branch-1'],
}) {
  return StaffDraft(
    id: id,
    name: name,
    mobile: mobile,
    username: username,
    password: password,
    role: role,
    branchIds: branchIds,
  );
}

ServiceDraft _service({String id = 'service-1', String name = 'Consultation', double? price = 200}) {
  return ServiceDraft(id: id, name: name, price: price);
}

void main() {
  group('validateSingleBranch', () {
    test('accepts a valid branch', () {
      expect(validateSingleBranch(_branch(), 0, allBranches: [_branch()]), isEmpty);
    });

    test('rejects invalid phone, maps URL, and branch code format', () {
      final errors = validateSingleBranch(
        _branch(code: 'bad code', mobile: '123', mapLocation: 'not a url'),
        0,
        allBranches: [_branch(code: 'bad code')],
      );

      expect(errors['branch-0-code'], isNotNull);
      expect(errors['branch-0-mobile'], contains('10-digit'));
      expect(errors['branch-0-map'], isNotNull);
    });

    test('rejects duplicate branch codes case-insensitively', () {
      final branches = [_branch(id: 'a', code: 'MAIN'), _branch(id: 'b', code: 'main')];

      final errors = validateBranches(branches);
      expect(errors['branch-1-code'], 'Branch code must be unique');
    });
  });

  group('validateStaff', () {
    test('accepts valid staff input', () {
      expect(validateStaff([_staff()], 1), isEmpty);
    });

    test('rejects weak passwords and invalid usernames', () {
      final errors = validateStaff([_staff(username: 'ab', password: 'short')], 1);

      expect(errors['staff-0-username'], isNotNull);
      expect(errors['staff-0-password'], contains('8 characters'));
    });

    test('rejects duplicate usernames', () {
      final errors = validateStaff([
        _staff(id: 'a', username: 'Sara_Hassan'),
        _staff(id: 'b', username: 'sara_hassan'),
      ], 1);

      expect(errors['staff-1-username'], 'Usernames must be unique');
    });
  });

  group('validateSingleStaff', () {
    test('accepts a valid staff member', () {
      expect(validateSingleStaff(_staff(), 0, allStaff: [_staff()], branchCount: 1), isEmpty);
    });

    test('rejects invalid fields for one member', () {
      final errors = validateSingleStaff(
        _staff(username: 'ab', password: 'short', branchIds: const []),
        0,
        allStaff: [_staff(username: 'ab', password: 'short', branchIds: const [])],
        branchCount: 1,
      );

      expect(errors['staff-0-username'], isNotNull);
      expect(errors['staff-0-password'], contains('8 characters'));
      expect(errors['staff-0-branches'], isNotNull);
    });
  });

  group('validateServices', () {
    test('accepts valid services', () {
      expect(validateServices([_service()]), isEmpty);
    });

    test('validateSingleService accepts a valid service', () {
      expect(validateSingleService(_service(), 0, allServices: [_service()]), isEmpty);
    });

    test('validateSingleService rejects invalid fields for one service', () {
      final errors = validateSingleService(
        _service(name: '', price: null),
        0,
        allServices: [_service(name: '', price: null)],
      );

      expect(errors['service-0-name'], isNotNull);
      expect(errors['service-0-price'], isNotNull);
    });

    test('rejects missing price, long names, and duplicate names', () {
      final errors = validateServices([
        _service(name: 'Consultation'),
        _service(id: 'service-2', name: ' consultation ', price: null),
      ]);

      expect(errors['service-1-name'], 'Service names must be unique');
      expect(errors['service-1-price'], isNotNull);
    });

    test('rejects prices with more than two decimal places', () {
      final errors = validateServices([_service(price: 12.345)]);

      expect(errors['service-0-price'], contains('two decimal places'));
    });
  });

  group('confirmedBranchIdsForSetup', () {
    test('confirms only branches that pass wizard validation', () {
      final branches = [_branch(id: 'valid', code: 'MAIN'), _branch(id: 'invalid', code: 'SECOND', mapLocation: '')];

      final confirmed = confirmedBranchIdsForSetup(branches);

      expect(confirmed, {'valid'});
    });
  });
}
