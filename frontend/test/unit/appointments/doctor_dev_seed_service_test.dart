import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/doctor_dev_seed_service.dart';
import 'package:ai_clinic/features/appointments/domain/doctor_dev_seed_data.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

class _FakeStaffAdminRepository extends Fake implements StaffAdminRepository {
  _FakeStaffAdminRepository(this.staff);

  final List<StaffListItem> staff;
  int listCalls = 0;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    listCalls += 1;
    return staff;
  }
}

class _FakeProvisioningRepository extends Fake implements ProvisioningRepository {
  _FakeProvisioningRepository({this.onCreate});

  final Future<CreateStaffAccountResult> Function(CreateStaffAccountInput input)? onCreate;
  final List<CreateStaffAccountInput> createCalls = [];

  @override
  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input) async {
    createCalls.add(input);
    if (onCreate != null) {
      return onCreate!(input);
    }
    return CreateStaffAccountResult(
      staffMemberId: 'staff-${createCalls.length}',
      username: input.username,
      assignedPassword: input.password,
    );
  }

}

AuthSessionContext _authContext({
  String? activeBranchId,
  List<String> branchIds = const [],
}) {
  return sampleAuthSessionContext(
    permissions: {'settings.manage_staff'},
    branchIds: branchIds,
    activeBranchId: activeBranchId,
  );
}

void main() {
  group('DoctorDevSeedService', () {
    test('invalid state: no branch resolvable returns error without repository calls', () async {
      final staff = _FakeStaffAdminRepository(const []);
      final provisioning = _FakeProvisioningRepository();
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext(activeBranchId: null, branchIds: const []));

      expect(outcome.created, 0);
      expect(outcome.skippedBecauseAlreadySeeded, isFalse);
      expect(outcome.errorMessage, 'Select an active branch before seeding doctors.');
      expect(outcome.isSuccess, isFalse);
      expect(staff.listCalls, 0);
      expect(provisioning.createCalls, isEmpty);
    });

    test('advanced: falls back to first branch when activeBranchId is null', () async {
      const branchId = '00000000-0000-4000-8000-000000000001';
      final staff = _FakeStaffAdminRepository(const []);
      final provisioning = _FakeProvisioningRepository();
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext(activeBranchId: null, branchIds: [branchId]));

      expect(outcome.isSuccess, isTrue);
      expect(outcome.created, DoctorDevSeedData.doctors.length);
      expect(provisioning.createCalls.every((call) => call.branchIds.single == branchId), isTrue);
    });

    test('edge case: already-seeded doctors are skipped', () async {
      final staff = _FakeStaffAdminRepository([
        StaffListItem(
          id: 'existing',
          fullName: '${DoctorDevSeedSpec.devNamePrefix}Dr Existing',
          role: StaffRole.doctor,
          isActive: true,
        ),
      ]);
      final provisioning = _FakeProvisioningRepository();
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext());

      expect(outcome.skippedBecauseAlreadySeeded, isTrue);
      expect(outcome.created, 0);
      expect(outcome.isSuccess, isTrue);
      expect(provisioning.createCalls, isEmpty);
    });

    test('trivial: happy path creates one account per doctor spec', () async {
      final staff = _FakeStaffAdminRepository(const []);
      final provisioning = _FakeProvisioningRepository();
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext());

      expect(outcome.isSuccess, isTrue);
      expect(outcome.created, DoctorDevSeedData.doctors.length);
      expect(provisioning.createCalls, hasLength(DoctorDevSeedData.doctors.length));
      expect(provisioning.createCalls.first.username, DoctorDevSeedData.doctors.first.username);
    });

    test('invalid state: RpcFailure mid-loop surfaces RPC message', () async {
      var calls = 0;
      final staff = _FakeStaffAdminRepository(const []);
      final provisioning = _FakeProvisioningRepository(
        onCreate: (_) async {
          calls += 1;
          if (calls == 2) {
            throw RpcFailure(
              const RpcResult(success: false, errorCode: 'USERNAME_TAKEN', errorMessage: 'Username already exists'),
            );
          }
          return CreateStaffAccountResult(
            staffMemberId: 'staff-$calls',
            username: 'dev_doc',
            assignedPassword: DoctorDevSeedData.defaultPassword,
          );
        },
      );
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext());

      expect(outcome.isSuccess, isFalse);
      expect(outcome.errorMessage, 'Username already exists');
      expect(outcome.created, 0);
    });

    test('regression: generic exception message is prefixed', () async {
      final staff = _FakeStaffAdminRepository(const []);
      final provisioning = _FakeProvisioningRepository(
        onCreate: (_) => throw Exception('disk full'),
      );
      final service = DoctorDevSeedService(staffAdmin: staff, provisioning: provisioning);

      final outcome = await service.seed(_authContext());

      expect(outcome.isSuccess, isFalse);
      expect(outcome.errorMessage, contains('Doctor seed failed: '));
    });

    test('trivial: isSuccess is true only when errorMessage is null', () async {
      const success = DoctorDevSeedOutcome(created: 1, skippedBecauseAlreadySeeded: false);
      const failure = DoctorDevSeedOutcome(
        created: 0,
        skippedBecauseAlreadySeeded: false,
        errorMessage: 'failed',
      );

      expect(success.isSuccess, isTrue);
      expect(failure.isSuccess, isFalse);
    });
  });
}
