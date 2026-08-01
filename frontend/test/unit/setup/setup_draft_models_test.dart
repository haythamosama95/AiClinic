import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setup draft factories', () {
    test('createDefaultSetup returns empty organization and one empty entity per list', () {
      final setup = createDefaultSetup();

      expect(setup.organization.name, isEmpty);
      expect(setup.organization.timezone, 'Africa/Cairo');
      expect(setup.organization.currency, 'EGP');
      expect(setup.branches, hasLength(1));
      expect(setup.staff, hasLength(1));
      expect(setup.services, hasLength(1));
      expect(setup.branches.single.isDraft, isTrue);
      expect(setup.staff.single.isDraft, isTrue);
      expect(setup.services.single.isDraft, isTrue);
    });

    test('createEmptyBranch has draft id and default working days', () {
      final branch = createEmptyBranch();

      expect(branch.name, isEmpty);
      expect(branch.code, isEmpty);
      expect(branch.mobile, isEmpty);
      expect(branch.mapLocation, isEmpty);
      expect(branch.isDraft, isTrue);
      expect(isSetupDraftEntityId(branch.id), isTrue);
      expect(branch.workingDays, hasLength(daysOfWeek.length));

      final fri = branch.workingDays.firstWhere((day) => day.day == 'fri');
      final sat = branch.workingDays.firstWhere((day) => day.day == 'sat');
      final mon = branch.workingDays.firstWhere((day) => day.day == 'mon');

      expect(fri.enabled, isFalse);
      expect(sat.enabled, isFalse);
      expect(mon.enabled, isTrue);
      expect(mon.openTime, '09:00');
      expect(mon.closeTime, '17:00');
    });

    test('createEmptyStaff has draft id and empty fields', () {
      final staff = createEmptyStaff();

      expect(staff.name, isEmpty);
      expect(staff.username, isEmpty);
      expect(staff.password, isEmpty);
      expect(staff.role, isEmpty);
      expect(staff.branchIds, isEmpty);
      expect(staff.isDraft, isTrue);
      expect(isSetupDraftEntityId(staff.id), isTrue);
    });

    test('createEmptyService has draft id and null price', () {
      final service = createEmptyService();

      expect(service.name, isEmpty);
      expect(service.price, isNull);
      expect(service.isDraft, isTrue);
      expect(isSetupDraftEntityId(service.id), isTrue);
    });

    test('createDefaultWorkingDays disables Friday and Saturday', () {
      final days = createDefaultWorkingDays();

      expect(days, hasLength(daysOfWeek.length));
      for (final meta in daysOfWeek) {
        final day = days.firstWhere((entry) => entry.day == meta.id);
        if (meta.id == 'fri' || meta.id == 'sat') {
          expect(day.enabled, isFalse, reason: '${meta.id} should be disabled');
        } else {
          expect(day.enabled, isTrue, reason: '${meta.id} should be enabled');
        }
        expect(day.openTime, '09:00');
        expect(day.closeTime, '17:00');
      }
    });
  });

  group('isSetupDraftEntityId', () {
    test('returns true for locally generated draft ids', () {
      expect(isSetupDraftEntityId('1730000000000_1'), isTrue);
      expect(isSetupDraftEntityId('${DateTime.now().microsecondsSinceEpoch}_42'), isTrue);
    });

    test('returns false for UUID-style backend ids', () {
      expect(isSetupDraftEntityId('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), isFalse);
      expect(isSetupDraftEntityId('branch-123'), isFalse);
    });

    test('returns false for ids without numeric prefix', () {
      expect(isSetupDraftEntityId('abc_123'), isFalse);
      expect(isSetupDraftEntityId('no_underscore'), isFalse);
      expect(isSetupDraftEntityId('_leading'), isFalse);
    });
  });

  group('staffRoleOptions', () {
    test('contains expected roles with labels', () {
      expect(staffRoleOptions, hasLength(4));
      expect(
        staffRoleOptions.map((option) => option.value).toList(),
        ['administrator', 'doctor', 'receptionist', 'lab_staff'],
      );
      expect(staffRoleOptions.first.label, 'Administrator');
      expect(STAFF_ROLE_OPTIONS, same(staffRoleOptions));
    });
  });

  group('copyWith', () {
    test('OrganizationDraft copyWith overrides selected fields', () {
      const original = OrganizationDraft(name: 'Clinic', timezone: 'Africa/Cairo', currency: 'EGP');

      final updated = original.copyWith(name: 'New Clinic', currency: 'USD');

      expect(updated.name, 'New Clinic');
      expect(updated.timezone, 'Africa/Cairo');
      expect(updated.currency, 'USD');
      expect(original.name, 'Clinic');
    });

    test('BranchDraft copyWith overrides selected fields', () {
      final original = createEmptyBranch().copyWith(name: 'Main', code: 'MAIN');

      final updated = original.copyWith(name: 'Downtown', isDraft: false);

      expect(updated.name, 'Downtown');
      expect(updated.code, 'MAIN');
      expect(updated.isDraft, isFalse);
      expect(original.name, 'Main');
      expect(original.isDraft, isTrue);
    });

    test('StaffDraft copyWith overrides selected fields', () {
      final original = createEmptyStaff().copyWith(username: 'alice', role: 'doctor', branchIds: ['b1']);

      final updated = original.copyWith(username: 'bob', isDraft: false);

      expect(updated.username, 'bob');
      expect(updated.role, 'doctor');
      expect(updated.branchIds, ['b1']);
      expect(updated.isDraft, isFalse);
      expect(original.username, 'alice');
    });

    test('ServiceDraft copyWith overrides selected fields and can clear price', () {
      final original = createEmptyService().copyWith(name: 'Consultation', price: 100);

      final renamed = original.copyWith(name: 'Follow-up');
      final cleared = original.copyWith(clearPrice: true);

      expect(renamed.name, 'Follow-up');
      expect(renamed.price, 100);
      expect(cleared.price, isNull);
      expect(original.name, 'Consultation');
    });
  });

  group('SetupDraft JSON roundtrip', () {
    test('toJson/fromJson preserves nested organization, branches, staff, and services', () {
      final branch = createEmptyBranch().copyWith(
        id: '1730000000000_1',
        name: 'Main Branch',
        code: 'MAIN',
        mobile: '+201000000000',
        mapLocation: 'Cairo',
        isDraft: true,
      );
      final staff = createEmptyStaff().copyWith(
        id: '1730000000000_2',
        name: 'Dr. Sam',
        mobile: '+201111111111',
        username: 'sam',
        password: 'secret',
        role: 'doctor',
        branchIds: [branch.id],
        isDraft: true,
      );
      final service = createEmptyService().copyWith(
        id: '1730000000000_3',
        name: 'Consultation',
        price: 250,
        isDraft: true,
      );
      final setup = SetupDraft(
        organization: const OrganizationDraft(name: 'AiClinic', timezone: 'Africa/Cairo', currency: 'EGP'),
        branches: [branch],
        staff: [staff],
        services: [service],
      );

      final decoded = SetupDraft.fromJson(setup.toJson());

      expect(decoded.organization.name, 'AiClinic');
      expect(decoded.organization.timezone, 'Africa/Cairo');
      expect(decoded.organization.currency, 'EGP');

      expect(decoded.branches, hasLength(1));
      expect(decoded.branches.single.name, 'Main Branch');
      expect(decoded.branches.single.code, 'MAIN');
      expect(decoded.branches.single.workingDays, hasLength(daysOfWeek.length));
      expect(decoded.branches.single.isDraft, isTrue);

      expect(decoded.staff, hasLength(1));
      expect(decoded.staff.single.username, 'sam');
      expect(decoded.staff.single.role, 'doctor');
      expect(decoded.staff.single.branchIds, [branch.id]);
      expect(decoded.staff.single.password, isEmpty);
      expect(decoded.staff.single.isDraft, isTrue);

      expect(decoded.services, hasLength(1));
      expect(decoded.services.single.name, 'Consultation');
      expect(decoded.services.single.price, 250);
      expect(decoded.services.single.isDraft, isTrue);
    });

    test('toJson does not persist staff passwords', () {
      final setup = createDefaultSetup().copyWith(
        staff: [
          createEmptyStaff().copyWith(username: 'alice', password: 'do-not-persist'),
        ],
      );

      final json = setup.toJson();
      final staffJson = (json['staff'] as List<dynamic>).single as Map<String, dynamic>;

      expect(staffJson['password'], isNull);
    });

    test('fromJson infers isDraft from backend UUID ids when field is absent', () {
      final json = {
        'organization': {'name': 'Clinic', 'timezone': 'Africa/Cairo', 'currency': 'EGP'},
        'branches': [
          {
            'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'name': 'Hydrated Branch',
            'code': 'HB',
            'mobile': '',
            'mapLocation': '',
            'workingDays': [
              {'day': 'mon', 'enabled': true, 'openTime': '08:00', 'closeTime': '16:00'},
            ],
          },
        ],
        'staff': [
          {
            'id': 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
            'name': 'Hydrated Staff',
            'mobile': '',
            'username': 'hydrated',
            'role': 'doctor',
            'branchIds': ['a1b2c3d4-e5f6-7890-abcd-ef1234567890'],
          },
        ],
        'services': [
          {'id': 'c3d4e5f6-a7b8-9012-cdef-123456789012', 'name': 'Hydrated Service', 'price': 99},
        ],
      };

      final setup = SetupDraft.fromJson(json);

      expect(setup.branches.single.isDraft, isFalse);
      expect(setup.staff.single.isDraft, isFalse);
      expect(setup.services.single.isDraft, isFalse);
    });
  });
}
