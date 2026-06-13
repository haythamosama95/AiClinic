import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/update_staff_member_input.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('StaffAdminRepository', () {
    late SettingsRpcTestClient client;
    late StaffAdminRepositoryImpl repository;

    setUp(() {
      client = SettingsRpcTestClient();
      repository = StaffAdminRepositoryImpl(client);
    });

    test('updateStaffMember sends role wire value and branch ids', () async {
      final id = await repository.updateStaffMember(
        UpdateStaffMemberInput(
          staffMemberId: '33333333-3333-4333-8333-333333333333',
          fullName: '  Updated  ',
          role: StaffRole.receptionist,
          branchIds: ['22222222-2222-4222-8222-222222222222'],
          phone: ' +1 ',
          primaryBranchId: '22222222-2222-4222-8222-222222222222',
        ),
      );

      expect(id, '33333333-3333-4333-8333-333333333333');
      expect(client.lastFunction, 'update_staff_member');
      expect(client.lastParams, containsPair('p_role', 'receptionist'));
      expect(client.lastParams, containsPair('p_full_name', 'Updated'));
      expect(client.lastParams?['p_branch_ids'], ['22222222-2222-4222-8222-222222222222']);
    });

    test('stupid usage: empty branch list rejected before RPC', () async {
      expect(
        () => repository.updateStaffMember(
          const UpdateStaffMemberInput(
            staffMemberId: '33333333-3333-4333-8333-333333333333',
            fullName: 'Name',
            role: StaffRole.doctor,
            branchIds: [],
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('stupid usage: blank full name rejected', () async {
      expect(
        () => repository.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: '33333333-3333-4333-8333-333333333333',
            fullName: '   ',
            role: StaffRole.doctor,
            branchIds: ['22222222-2222-4222-8222-222222222222'],
          ),
        ),
        throwsA(isA<RpcFailure>()),
      );
    });

    test('setStaffActive passes deactivate flag', () async {
      await repository.setStaffActive(staffMemberId: '33333333-3333-4333-8333-333333333333', isActive: false);
      expect(client.lastFunction, 'set_staff_active');
      expect(client.lastParams, containsPair('p_is_active', false));
    });

    test('deleteStaffMember sends delete_staff_member parameters', () async {
      await repository.deleteStaffMember(staffMemberId: '33333333-3333-4333-8333-333333333333');
      expect(client.lastFunction, 'delete_staff_member');
      expect(client.lastParams, containsPair('p_staff_member_id', '33333333-3333-4333-8333-333333333333'));
    });

    test('listStaff filters active and inactive rows', () async {
      final client = SettingsTableTestClient({
        'staff_members': [
          {'id': 's1', 'full_name': 'Active User', 'role': 'doctor', 'is_active': true, 'is_deleted': false},
          {'id': 's2', 'full_name': 'Inactive User', 'role': 'receptionist', 'is_active': false, 'is_deleted': false},
          {'id': 'bad', 'full_name': '', 'role': 'doctor', 'is_active': true, 'is_deleted': false},
        ],
      });
      final repo = StaffAdminRepositoryImpl(client);

      final active = await repo.listStaff(filter: StaffListFilter.active);
      final inactive = await repo.listStaff(filter: StaffListFilter.inactive);

      expect(active.map((s) => s.fullName), ['Active User']);
      expect(inactive.map((s) => s.fullName), ['Inactive User']);
    });

    test('listStaff returns staff sorted alphabetically by full name', () async {
      final client = SettingsTableTestClient({
        'staff_members': [
          {'id': 's3', 'full_name': 'Zoe', 'role': 'lab_staff', 'is_active': true, 'is_deleted': false},
          {'id': 's1', 'full_name': 'Alice', 'role': 'administrator', 'is_active': true, 'is_deleted': false},
          {'id': 's2', 'full_name': 'bob', 'role': 'doctor', 'is_active': true, 'is_deleted': false},
        ],
      });
      final repo = StaffAdminRepositoryImpl(client);

      final staff = await repo.listStaff();

      expect(staff.map((s) => s.fullName), ['Alice', 'bob', 'Zoe']);
    });

    test('advanced: cross-org denial surfaces from RPC', () async {
      client.rpcResults['update_staff_member'] = {
        'success': false,
        'error_code': 'CROSS_ORG_DENIED',
        'error_message': 'Outside scope',
      };

      expect(
        () => repository.updateStaffMember(
          UpdateStaffMemberInput(
            staffMemberId: '33333333-3333-4333-8333-333333333333',
            fullName: 'X',
            role: StaffRole.doctor,
            branchIds: ['22222222-2222-4222-8222-222222222222'],
          ),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'CROSS_ORG_DENIED')),
      );
    });
  });
}
