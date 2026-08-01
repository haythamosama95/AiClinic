import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/organization_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_organization_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/fetch_organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/settings_test_support.dart';

void main() {
  group('clinicSetupOrganizationProvider', () {
    ProviderContainer createContainer({
      required MutableAuthSessionNotifier auth,
      required OrganizationRepository organizationRepository,
    }) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          fetchOrganizationProfileUseCaseProvider.overrideWith(
            (ref) => FetchOrganizationProfile(organizationRepository),
          ),
        ],
      );
    }

    test('returns null when organizationId is null', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      final repository = _FakeOrganizationRepository.neverCalled();
      final container = createContainer(
        auth: auth,
        organizationRepository: repository,
      );
      addTearDown(container.dispose);

      final profile = await container.read(clinicSetupOrganizationProvider.future);

      expect(profile, isNull);
      expect(repository.fetchCallCount, 0);
    });

    test('returns null when organizationId is empty', () async {
      final context = sampleAuthSessionContext().copyWith(organizationId: '');
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(status: AuthSessionStatus.authenticated, context: context),
      );
      final repository = _FakeOrganizationRepository.neverCalled();
      final container = createContainer(auth: auth, organizationRepository: repository);
      addTearDown(container.dispose);

      final profile = await container.read(clinicSetupOrganizationProvider.future);

      expect(profile, isNull);
      expect(repository.fetchCallCount, 0);
    });

    test('loads organization profile when organizationId is present', () async {
      const orgId = '20202020-2020-4020-8020-202020202020';
      final expected = sampleOrganizationProfile(id: orgId, currencyCode: 'USD', timezone: 'UTC');
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext().copyWith(organizationId: orgId),
        ),
      );
      final repository = _FakeOrganizationRepository(profile: expected);
      final container = createContainer(auth: auth, organizationRepository: repository);
      addTearDown(container.dispose);

      final profile = await container.read(clinicSetupOrganizationProvider.future);

      expect(profile, expected);
      expect(repository.fetchCallCount, 1);
      expect(repository.lastOrganizationId, orgId);
    });
  });

  group('clinicSetupBranchesProvider', () {
    ProviderContainer createContainer({
      required MutableAuthSessionNotifier auth,
      required BranchRepository branchRepository,
    }) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => auth),
          listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(branchRepository)),
        ],
      );
    }

    test('returns empty list when organizationId is null', () async {
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      final repository = _FakeBranchRepository.neverCalled();
      final container = createContainer(auth: auth, branchRepository: repository);
      addTearDown(container.dispose);

      final branches = await container.read(clinicSetupBranchesProvider.future);

      expect(branches, isEmpty);
      expect(repository.listCallCount, 0);
    });

    test('returns empty list when organizationId is empty', () async {
      final context = sampleAuthSessionContext().copyWith(organizationId: '');
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(status: AuthSessionStatus.authenticated, context: context),
      );
      final repository = _FakeBranchRepository.neverCalled();
      final container = createContainer(auth: auth, branchRepository: repository);
      addTearDown(container.dispose);

      final branches = await container.read(clinicSetupBranchesProvider.future);

      expect(branches, isEmpty);
      expect(repository.listCallCount, 0);
    });

    test('loads branches when organizationId is present', () async {
      const orgId = '20202020-2020-4020-8020-202020202020';
      final expected = [sampleBranch(id: 'b1', name: 'Main Branch'), sampleBranch(id: 'b2', name: 'Annex')];
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext().copyWith(organizationId: orgId),
        ),
      );
      final repository = _FakeBranchRepository(branches: expected);
      final container = createContainer(auth: auth, branchRepository: repository);
      addTearDown(container.dispose);

      final branches = await container.read(clinicSetupBranchesProvider.future);

      expect(branches, expected);
      expect(repository.listCallCount, 1);
      expect(repository.lastOrganizationId, orgId);
    });
  });
}

class _FakeOrganizationRepository implements OrganizationRepository {
  _FakeOrganizationRepository({required this.profile}) : fetchCallCount = 0;

  _FakeOrganizationRepository.neverCalled() : profile = null, fetchCallCount = 0;

  final OrganizationProfile? profile;
  int fetchCallCount;
  String? lastOrganizationId;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) async {
    fetchCallCount++;
    lastOrganizationId = organizationId;
    return profile;
  }

  @override
  Future<String> updateOrganization(UpdateOrganizationInput input) => throw UnimplementedError();
}

class _FakeBranchRepository implements BranchRepository {
  _FakeBranchRepository({required this.branches}) : listCallCount = 0;

  _FakeBranchRepository.neverCalled() : branches = const [], listCallCount = 0;

  final List<BranchListItem> branches;
  int listCallCount;
  String? lastOrganizationId;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    listCallCount++;
    lastOrganizationId = organizationId;
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
