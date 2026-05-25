import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ProvisioningRepository RPC contract', () {
    late RpcCaptureSupabaseClient client;
    late ProvisioningRepositoryImpl repository;

    setUp(() {
      client = RpcCaptureSupabaseClient();
      repository = ProvisioningRepositoryImpl(client);
    });

    test('createStaffAccount sends required contract keys and normalizes username/name', () async {
      final result = await repository.createStaffAccount(
        const CreateStaffAccountInput(
          username: '  NewStaff ',
          password: 'Initial1!',
          fullName: '  Jane Doe ',
          role: StaffRole.receptionist,
          branchIds: ['22222222-2222-4222-8222-222222222222'],
          primaryBranchId: '22222222-2222-4222-8222-222222222222',
        ),
      );

      expect(client.lastFunction, 'create_staff_account');
      expect(client.lastParams, containsPair('p_username', 'newstaff'));
      expect(client.lastParams, containsPair('p_password', 'Initial1!'));
      expect(client.lastParams, containsPair('p_full_name', 'Jane Doe'));
      expect(client.lastParams, containsPair('p_role', 'receptionist'));
      expect(client.lastParams, containsPair('p_branch_ids', ['22222222-2222-4222-8222-222222222222']));
      expect(client.lastParams, containsPair('p_primary_branch_id', '22222222-2222-4222-8222-222222222222'));
      expect(result.username, 'newstaff');
    });

    test('createStaffAccount omits primary branch when null', () async {
      await repository.createStaffAccount(
        const CreateStaffAccountInput(
          username: 'doctor1',
          password: 'x',
          fullName: 'A',
          role: StaffRole.doctor,
          branchIds: ['22222222-2222-4222-8222-222222222222'],
        ),
      );

      expect(client.lastParams, isNot(contains('p_primary_branch_id')));
    });

    test('createStaffAccount forwards empty branch list when UI guard skipped', () async {
      await repository.createStaffAccount(
        const CreateStaffAccountInput(
          username: 'doctor1',
          password: 'x',
          fullName: 'A',
          role: StaffRole.doctor,
          branchIds: [],
        ),
      );

      expect(client.lastParams, containsPair('p_branch_ids', <String>[]));
    });

    test('resetStaffPassword sends contract keys', () async {
      await repository.resetStaffPassword(
        staffMemberId: '33333333-3333-4333-8333-333333333333',
        newPassword: '  NewPass2! ',
      );

      expect(client.lastFunction, 'admin_reset_staff_password');
      expect(client.lastParams, containsPair('p_staff_member_id', '33333333-3333-4333-8333-333333333333'));
      expect(client.lastParams, containsPair('p_new_password', '  NewPass2! '));
    });

    test('resetStaffPassword forwards whitespace password when caller skips trim', () async {
      await repository.resetStaffPassword(staffMemberId: '33333333-3333-4333-8333-333333333333', newPassword: '   ');

      expect(client.lastParams, containsPair('p_new_password', '   '));
    });
  });
}
