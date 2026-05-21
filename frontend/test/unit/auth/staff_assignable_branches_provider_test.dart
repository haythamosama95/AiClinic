import 'package:ai_clinic/features/auth/data/provisioning_repository.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _activeBranchId = '00000000-0000-4000-8000-000000000101';
const _inactiveBranchId = '00000000-0000-4000-8000-000000000102';

class _BranchListProvisioningRepository extends ProvisioningRepository {
  _BranchListProvisioningRepository() : super(SupabaseClient('http://localhost', 'anon'));

  @override
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds) async {
    expect(branchIds, [_activeBranchId, _inactiveBranchId]);
    return const [BranchSummary(id: _activeBranchId, name: 'Active Wing')];
  }
}

class _SessionWithTwoClaimedBranches extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() => AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      branchIds: const [_activeBranchId, _inactiveBranchId],
      activeBranchId: _activeBranchId,
      permissions: RolePermissionSeed.owner,
    ),
  );
}

void main() {
  test('staffAssignableBranchesProvider returns only active branches from repository filter', () async {
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_SessionWithTwoClaimedBranches.new),
        provisioningRepositoryProvider.overrideWithValue(_BranchListProvisioningRepository()),
      ],
    );
    addTearDown(container.dispose);

    final branches = await container.read(staffAssignableBranchesProvider.future);

    expect(branches, hasLength(1));
    expect(branches.first.id, _activeBranchId);
    expect(branches.first.name, 'Active Wing');
  });

  test('staffAssignableBranchesProvider returns empty when session has no branch ids', () async {
    final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
    addTearDown(container.dispose);

    final branches = await container.read(staffAssignableBranchesProvider.future);

    expect(branches, isEmpty);
  });
}
