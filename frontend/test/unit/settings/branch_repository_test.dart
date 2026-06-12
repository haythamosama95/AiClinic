import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/create_branch_input.dart';
import 'package:ai_clinic/features/settings/domain/update_branch_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('BranchRepository', () {
    late SettingsRpcTestClient client;
    late BranchRepositoryImpl repository;

    setUp(() {
      client = SettingsRpcTestClient();
      repository = BranchRepositoryImpl(client);
    });

    test('createBranch sends manage_create_branch parameters', () async {
      final id = await repository.createBranch(
        CreateBranchInput(
          name: '  North  ',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: ' N1 ',
          address: ' 1 St ',
          phone: ' 555 ',
          mapsUrl: ' https://m ',
        ),
      );

      expect(id, '44444444-4444-4444-8444-444444444444');
      expect(client.lastFunction, 'manage_create_branch');
      expect(client.lastParams, containsPair('p_name', 'North'));
      expect(client.lastParams, containsPair('p_code', 'N1'));
    });

    test('stupid usage: empty branch name rejected locally', () async {
      expect(
        () => repository.createBranch(
          CreateBranchInput(name: '  ', workingSchedule: BranchWorkingSchedule.defaultSchedule()),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'INVALID_INPUT')),
      );
    });

    test('setBranchActive maps LAST_ACTIVE_BRANCH from server', () async {
      client.rpcResults['set_branch_active'] = {
        'success': false,
        'error_code': 'LAST_ACTIVE_BRANCH',
        'error_message': 'Cannot deactivate the last active branch.',
      };

      expect(
        () => repository.setBranchActive(branchId: '22222222-2222-4222-8222-222222222222', isActive: false),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'LAST_ACTIVE_BRANCH')),
      );
    });

    test('updateBranch omits optional empty fields but keeps name', () async {
      await repository.updateBranch(
        UpdateBranchInput(
          branchId: '22222222-2222-4222-8222-222222222222',
          name: 'Renamed',
          workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          code: '',
        ),
      );

      expect(client.lastFunction, 'update_branch');
      expect(client.lastParams, containsPair('p_name', 'Renamed'));
      expect(client.lastParams, containsPair('p_code', ''));
    });

    test('listBranches filters active and inactive rows', () async {
      const orgId = '11111111-1111-4111-8111-111111111111';
      final client = SettingsTableTestClient({
        'branches': [
          {'id': 'b1', 'name': 'Active', 'is_active': true, 'is_deleted': false, 'organization_id': orgId},
          {'id': 'b2', 'name': 'Closed', 'is_active': false, 'is_deleted': false, 'organization_id': orgId},
          {'id': 'bad', 'name': '', 'is_active': true, 'is_deleted': false, 'organization_id': orgId},
        ],
      });
      final repo = BranchRepositoryImpl(client);

      final active = await repo.listBranches(organizationId: orgId, filter: BranchListFilter.active);
      final inactive = await repo.listBranches(organizationId: orgId, filter: BranchListFilter.inactive);
      final all = await repo.listBranches(organizationId: orgId);

      expect(active.map((b) => b.name), ['Active']);
      expect(inactive.map((b) => b.name), ['Closed']);
      expect(all.map((b) => b.name), containsAll(['Active', 'Closed']));
      expect(all, hasLength(2));
    });

    test('listBranches returns branches in creation order', () async {
      const orgId = '11111111-1111-4111-8111-111111111111';
      final client = SettingsTableTestClient({
        'branches': [
          {
            'id': 'b-new',
            'name': 'Alpha Branch',
            'is_active': true,
            'is_deleted': false,
            'organization_id': orgId,
            'created_at': '2026-06-13T12:00:00Z',
          },
          {
            'id': 'b-old',
            'name': 'Zulu Branch',
            'is_active': true,
            'is_deleted': false,
            'organization_id': orgId,
            'created_at': '2026-01-01T12:00:00Z',
          },
        ],
      });
      final repo = BranchRepositoryImpl(client);

      final branches = await repo.listBranches(organizationId: orgId);

      expect(branches.map((b) => b.id), ['b-old', 'b-new']);
    });

    test('advanced: RPC_NOT_APPLIED when migration missing', () async {
      final client = SettingsRpcTestClient(
        rpcException: const PostgrestException(
          message: 'Could not find the function public.manage_create_branch',
          code: 'PGRST202',
        ),
      );

      expect(
        () => BranchRepositoryImpl(
          client,
        ).createBranch(CreateBranchInput(name: 'X', workingSchedule: BranchWorkingSchedule.defaultSchedule())),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_NOT_APPLIED')),
      );
    });

    test('corner case: duplicate code error code preserved', () async {
      client.rpcResults['manage_create_branch'] = {
        'success': false,
        'error_code': 'DUPLICATE_CODE',
        'error_message': 'Duplicate',
      };

      expect(
        () => repository.createBranch(
          CreateBranchInput(name: 'X', workingSchedule: BranchWorkingSchedule.defaultSchedule(), code: 'MAIN'),
        ),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'DUPLICATE_CODE')),
      );
    });
  });
}
