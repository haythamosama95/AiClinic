import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/patients/presentation/providers/active_branch_name_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  group('activeBranchNameProvider', () {
    const activeBranchId = '00000000-0000-4000-8000-000000000001';
    const fallback = 'your active branch';

    ProviderContainer createContainer({
      required MutableAuthSessionNotifier auth,
      required BranchRepository branchRepository,
    }) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          listBranchesUseCaseProvider.overrideWith(
            (ref) => ListBranches(branchRepository),
          ),
        ],
      );
    }

    test('resolves the active branch name from list branches', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            activeBranchId: activeBranchId,
          ),
        ),
      );
      final container = createContainer(
        auth: auth,
        branchRepository: _FakeBranchRepository(
          branches: const [
            BranchListItem(id: activeBranchId, name: 'Main Clinic', isActive: true),
            BranchListItem(id: '00000000-0000-4000-8000-000000000002', name: 'Annex', isActive: true),
          ],
        ),
      );
      addTearDown(container.dispose);

      final name = await container.read(activeBranchNameProvider.future);

      expect(name, 'Main Clinic');
    });

    test('falls back when organizationId is null', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      final container = createContainer(
        auth: auth,
        branchRepository: _FakeBranchRepository.neverCalled(),
      );
      addTearDown(container.dispose);

      final name = await container.read(activeBranchNameProvider.future);

      expect(name, fallback);
    });

    test('falls back when organizationId is empty', () async {
      final context = sampleAuthSessionContext().copyWith(organizationId: '');
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(status: AuthSessionStatus.authenticated, context: context),
      );
      final container = createContainer(
        auth: auth,
        branchRepository: _FakeBranchRepository.neverCalled(),
      );
      addTearDown(container.dispose);

      final name = await container.read(activeBranchNameProvider.future);

      expect(name, fallback);
    });

    test('falls back when active branch id is not in the branch list', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            activeBranchId: '99999999-9999-4999-8999-999999999999',
          ),
        ),
      );
      final container = createContainer(
        auth: auth,
        branchRepository: _FakeBranchRepository(
          branches: const [
            BranchListItem(id: activeBranchId, name: 'Main Clinic', isActive: true),
          ],
        ),
      );
      addTearDown(container.dispose);

      final name = await container.read(activeBranchNameProvider.future);

      expect(name, fallback);
    });

    test('surfaces an error when list branches throws', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(),
        ),
      );
      final container = createContainer(
        auth: auth,
        branchRepository: _FakeBranchRepository.throwsOnList(),
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(activeBranchNameProvider.future),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branches}) : listError = null;

  _FakeBranchRepository.neverCalled() : branches = const [], listError = null;

  _FakeBranchRepository.throwsOnList()
    : branches = const [],
      listError = StateError('branch list failed');

  final List<BranchListItem> branches;
  final Object? listError;
  int listCallCount = 0;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    listCallCount++;
    if (listError != null) {
      throw listError!;
    }
    return branches;
  }

  @override
  Future<String> createBranch(CreateBranchInput input) => throw UnimplementedError();

  @override
  Future<String> updateBranch(UpdateBranchInput input) => throw UnimplementedError();

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> deleteBranch({required String branchId}) => throw UnimplementedError();
}
