import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/branch_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/organization_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/repositories/staff_admin_repository.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_member_detail.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_organization_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/create_branch.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/delete_branch.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/fetch_organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/set_branch_active.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/update_branch.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/update_organization.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/update_staff_member.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/delete_staff_member.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/setup/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/setup/domain/admin_update_staff_username_result.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/domain/staff_member_summary.dart';
import 'package:ai_clinic/features/setup/domain/usecases/create_staff_account.dart';
import 'package:ai_clinic/features/setup/domain/usecases/reset_staff_password.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/domain/usecases/update_staff_username.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/settings_test_support.dart';

void main() {
  group('ClinicManagementNotifier', () {
    const orgId = '00000000-0000-4000-8000-000000000020';
    final organization = sampleOrganizationProfile(id: orgId);
    final branches = [sampleBranch()];
    const staff = [
      StaffListItem(
        id: '22222222-2222-4222-8222-222222222222',
        fullName: 'Jane Doe',
        role: StaffRole.doctor,
        isActive: true,
        username: 'jane',
      ),
    ];

    late _TrackingOrganizationRepository organizationRepository;
    late _TrackingBranchRepository branchRepository;
    late _TrackingStaffAdminRepository staffRepository;
    late _TrackingProvisioningRepository provisioningRepository;

    AuthSessionState fullAccessAuth() {
      return AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(
          role: StaffRole.administrator,
          permissions: {PermissionKeys.manageBranches, PermissionKeys.manageStaff},
        ),
      );
    }

    ProviderContainer container({AuthSessionState? authState}) {
      organizationRepository = _TrackingOrganizationRepository(profile: organization);
      branchRepository = _TrackingBranchRepository(branches: branches);
      staffRepository = _TrackingStaffAdminRepository(staff: staff);
      provisioningRepository = _TrackingProvisioningRepository();

      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState ?? fullAccessAuth())),
          fetchOrganizationProfileUseCaseProvider.overrideWith(
            (ref) => FetchOrganizationProfile(organizationRepository),
          ),
          updateOrganizationUseCaseProvider.overrideWith((ref) => UpdateOrganization(organizationRepository)),
          listBranchesUseCaseProvider.overrideWith((ref) => ListBranches(branchRepository)),
          createBranchUseCaseProvider.overrideWith((ref) => CreateBranch(branchRepository)),
          updateBranchUseCaseProvider.overrideWith((ref) => UpdateBranch(branchRepository)),
          setBranchActiveUseCaseProvider.overrideWith((ref) => SetBranchActive(branchRepository)),
          deleteBranchUseCaseProvider.overrideWith((ref) => DeleteBranch(branchRepository)),
          listStaffUseCaseProvider.overrideWith((ref) => ListStaff(staffRepository)),
          updateStaffMemberUseCaseProvider.overrideWith((ref) => UpdateStaffMember(staffRepository)),
          deleteStaffMemberUseCaseProvider.overrideWith((ref) => DeleteStaffMember(staffRepository)),
          createStaffAccountUseCaseProvider.overrideWith((ref) => CreateStaffAccount(provisioningRepository)),
          resetStaffPasswordUseCaseProvider.overrideWith((ref) => ResetStaffPassword(provisioningRepository)),
          updateStaffUsernameUseCaseProvider.overrideWith((ref) => UpdateStaffUsername(provisioningRepository)),
        ],
      );
    }

    test('build loads org, branches, and staff when auth permits', () async {
      final c = container();
      addTearDown(c.dispose);

      final state = await c.read(clinicManagementProvider.future);

      expect(state.organization, organization);
      expect(state.branches, branches);
      expect(state.staff, staff);
      expect(organizationRepository.fetchCallCount, 1);
      expect(branchRepository.listCallCount, 1);
      expect(staffRepository.listCallCount, 1);
    });

    test('build returns empty when no organizationId', () async {
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true),
        ),
      );
      addTearDown(c.dispose);

      final state = await c.read(clinicManagementProvider.future);

      expect(state.organization, isNull);
      expect(state.branches, isEmpty);
      expect(state.staff, isEmpty);
      expect(organizationRepository.fetchCallCount, 0);
      expect(branchRepository.listCallCount, 0);
      expect(staffRepository.listCallCount, 0);
    });

    test('build skips org when no permission, branches when no branch permission, staff when no staff permission', () async {
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.doctor,
            permissions: {PermissionKeys.manageStaff},
          ),
        ),
      );
      addTearDown(c.dispose);

      final state = await c.read(clinicManagementProvider.future);

      expect(state.organization, isNull);
      expect(state.branches, isEmpty);
      expect(state.staff, staff);
      expect(organizationRepository.fetchCallCount, 0);
      expect(branchRepository.listCallCount, 0);
      expect(staffRepository.listCallCount, 1);
    });

    test('build loads org and branches for branch manager without staff permission', () async {
      final c = container(
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            role: StaffRole.doctor,
            permissions: {PermissionKeys.manageBranches},
          ),
        ),
      );
      addTearDown(c.dispose);

      final state = await c.read(clinicManagementProvider.future);

      expect(state.organization, organization);
      expect(state.branches, branches);
      expect(state.staff, isEmpty);
      expect(organizationRepository.fetchCallCount, 1);
      expect(branchRepository.listCallCount, 1);
      expect(staffRepository.listCallCount, 0);
    });

    test('reload refreshes data', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(clinicManagementProvider.future);

      organizationRepository.profile = sampleOrganizationProfile(id: orgId, name: 'Reloaded Clinic');
      branchRepository.branches = [sampleBranch(name: 'Reloaded Branch')];
      staffRepository.staff = const [
        StaffListItem(
          id: '33333333-3333-4333-8333-333333333333',
          fullName: 'Reloaded Staff',
          role: StaffRole.receptionist,
          isActive: true,
        ),
      ];

      await c.read(clinicManagementProvider.notifier).reload();
      final state = c.read(clinicManagementProvider).value!;

      expect(state.organization?.name, 'Reloaded Clinic');
      expect(state.branches.single.name, 'Reloaded Branch');
      expect(state.staff.single.fullName, 'Reloaded Staff');
      expect(organizationRepository.fetchCallCount, 2);
      expect(branchRepository.listCallCount, 2);
      expect(staffRepository.listCallCount, 2);
    });

    group('updateOrganization', () {
      test('success reloads data and invalidates staffListProvider', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        await c.read(staffListProvider.future);
        final staffCallsBefore = staffRepository.listCallCount;

        organizationRepository.profile = sampleOrganizationProfile(id: orgId, name: 'Updated Clinic');
        await c.read(clinicManagementProvider.notifier).updateOrganization(organizationRepository.profile!);

        final state = c.read(clinicManagementProvider).value!;
        expect(state.organization?.name, 'Updated Clinic');
        expect(organizationRepository.updateCallCount, 1);
        expect(staffRepository.listCallCount, greaterThan(staffCallsBefore));
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        organizationRepository.updateError = RpcFailure(const RpcResult(success: false, errorCode: 'FORBIDDEN'));

        await c.read(clinicManagementProvider.notifier).updateOrganization(
          sampleOrganizationProfile(id: orgId, name: 'Should Not Stick'),
        );

        expect(c.read(clinicManagementProvider).hasError, isFalse);
        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('addBranch', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        branchRepository.branches = [...branches, sampleBranch(id: '55555555-5555-4555-8555-555555555555', name: 'Annex')];

        await c.read(clinicManagementProvider.notifier).addBranch(
          CreateBranchInput(name: 'Annex', workingSchedule: BranchWorkingSchedule.defaultSchedule()),
        );

        expect(branchRepository.createCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.branches, hasLength(2));
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        branchRepository.createError = RpcFailure(const RpcResult(success: false, errorCode: 'DUPLICATE_CODE'));

        await c.read(clinicManagementProvider.notifier).addBranch(
          CreateBranchInput(name: 'Annex', workingSchedule: BranchWorkingSchedule.defaultSchedule()),
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('updateBranch', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        final branchId = branches.first.id;
        branchRepository.branches = [sampleBranch(id: branchId, name: 'Renamed Branch')];

        await c.read(clinicManagementProvider.notifier).updateBranch(
          UpdateBranchInput(
            branchId: branchId,
            name: 'Renamed Branch',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        );

        expect(branchRepository.updateCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.branches.single.name, 'Renamed Branch');
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        branchRepository.updateError = RpcFailure(const RpcResult(success: false, errorCode: 'BRANCH_NOT_FOUND'));

        await c.read(clinicManagementProvider.notifier).updateBranch(
          UpdateBranchInput(
            branchId: branches.first.id,
            name: 'Missing',
            workingSchedule: BranchWorkingSchedule.defaultSchedule(),
          ),
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('removeBranch', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        branchRepository.branches = const [];

        await c.read(clinicManagementProvider.notifier).removeBranch(branches.first.id);

        expect(branchRepository.deleteCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.branches, isEmpty);
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        branchRepository.deleteError = RpcFailure(const RpcResult(success: false, errorCode: 'BRANCH_STILL_ACTIVE'));

        await c.read(clinicManagementProvider.notifier).removeBranch(branches.first.id);

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('toggleBranchActive', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        branchRepository.branches = [sampleBranch(isActive: false)];

        await c.read(clinicManagementProvider.notifier).toggleBranchActive(
          branchId: branches.first.id,
          isActive: false,
        );

        expect(branchRepository.setActiveCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.branches.single.isActive, isFalse);
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        branchRepository.setActiveError = RpcFailure(const RpcResult(success: false, errorCode: 'LAST_ACTIVE_BRANCH'));

        await c.read(clinicManagementProvider.notifier).toggleBranchActive(
          branchId: branches.first.id,
          isActive: false,
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('addStaff', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        staffRepository.staff = [
          ...staff,
          const StaffListItem(
            id: '44444444-4444-4444-8444-444444444444',
            fullName: 'New Hire',
            role: StaffRole.receptionist,
            isActive: true,
          ),
        ];

        await c.read(clinicManagementProvider.notifier).addStaff(
          const CreateStaffAccountInput(
            username: 'newhire',
            password: 'Password1',
            fullName: 'New Hire',
            role: StaffRole.receptionist,
            branchIds: ['00000000-0000-4000-8000-000000000001'],
          ),
        );

        expect(provisioningRepository.createCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.staff, hasLength(2));
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        provisioningRepository.createError = RpcFailure(const RpcResult(success: false, errorCode: 'FORBIDDEN'));

        await c.read(clinicManagementProvider.notifier).addStaff(
          const CreateStaffAccountInput(
            username: 'newhire',
            password: 'Password1',
            fullName: 'New Hire',
            role: StaffRole.receptionist,
            branchIds: ['00000000-0000-4000-8000-000000000001'],
          ),
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('updateStaff', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        staffRepository.staff = [
          const StaffListItem(
            id: '22222222-2222-4222-8222-222222222222',
            fullName: 'Updated Name',
            role: StaffRole.doctor,
            isActive: true,
          ),
        ];

        await c.read(clinicManagementProvider.notifier).updateStaff(
          const UpdateStaffMemberInput(
            staffMemberId: '22222222-2222-4222-8222-222222222222',
            fullName: 'Updated Name',
            role: StaffRole.doctor,
            branchIds: ['00000000-0000-4000-8000-000000000001'],
          ),
        );

        expect(staffRepository.updateCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.staff.single.fullName, 'Updated Name');
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        staffRepository.updateError = RpcFailure(const RpcResult(success: false, errorCode: 'STAFF_NOT_FOUND'));

        await c.read(clinicManagementProvider.notifier).updateStaff(
          const UpdateStaffMemberInput(
            staffMemberId: '22222222-2222-4222-8222-222222222222',
            fullName: 'Updated Name',
            role: StaffRole.doctor,
            branchIds: ['00000000-0000-4000-8000-000000000001'],
          ),
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('updateStaffFromForm', () {
      const staffMemberId = '22222222-2222-4222-8222-222222222222';
      const formValues = StaffFormValues(
        fullName: 'Jane Doe',
        username: 'newusername',
        password: 'Password1',
        role: StaffRole.doctor,
        branchIds: ['00000000-0000-4000-8000-000000000001'],
      );

      test('success updates profile, username, and password then reloads', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);

        await c.read(clinicManagementProvider.notifier).updateStaffFromForm(
          staffMemberId: staffMemberId,
          values: formValues,
          originalUsername: 'jane',
        );

        expect(staffRepository.updateCallCount, 1);
        expect(provisioningRepository.updateUsernameCallCount, 1);
        expect(provisioningRepository.resetPasswordCallCount, 1);
        expect(provisioningRepository.lastNewUsername, 'newusername');
        expect(provisioningRepository.lastNewPassword, 'Password1');
      });

      test('skips username and password RPCs when unchanged', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);

        await c.read(clinicManagementProvider.notifier).updateStaffFromForm(
          staffMemberId: staffMemberId,
          values: formValues.copyWith(username: 'jane', password: ''),
          originalUsername: 'jane',
        );

        expect(staffRepository.updateCallCount, 1);
        expect(provisioningRepository.updateUsernameCallCount, 0);
        expect(provisioningRepository.resetPasswordCallCount, 0);
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        provisioningRepository.updateUsernameError = RpcFailure(
          const RpcResult(success: false, errorCode: 'INVALID_INPUT'),
        );

        await c.read(clinicManagementProvider.notifier).updateStaffFromForm(
          staffMemberId: staffMemberId,
          values: formValues,
          originalUsername: 'jane',
        );

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    group('removeStaff', () {
      test('success reloads data', () async {
        final c = container();
        addTearDown(c.dispose);

        await c.read(clinicManagementProvider.future);
        staffRepository.staff = const [];

        await c.read(clinicManagementProvider.notifier).removeStaff('22222222-2222-4222-8222-222222222222');

        expect(staffRepository.deleteCallCount, 1);
        expect(c.read(clinicManagementProvider).value!.staff, isEmpty);
      });

      test('failure restores previous state', () async {
        final c = container();
        addTearDown(c.dispose);

        final initial = await c.read(clinicManagementProvider.future);
        staffRepository.deleteError = RpcFailure(const RpcResult(success: false, errorCode: 'STAFF_STILL_ACTIVE'));

        await c.read(clinicManagementProvider.notifier).removeStaff('22222222-2222-4222-8222-222222222222');

        expect(c.read(clinicManagementProvider).value, initial);
      });
    });

    test('successful mutation invalidates staffListProvider', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(clinicManagementProvider.future);
      await c.read(staffListProvider.future);
      final staffCallsBefore = staffRepository.listCallCount;

      branchRepository.branches = [...branches, sampleBranch(id: '66666666-6666-4666-8666-666666666666', name: 'East')];
      await c.read(clinicManagementProvider.notifier).addBranch(
        CreateBranchInput(name: 'East', workingSchedule: BranchWorkingSchedule.defaultSchedule()),
      );

      await c.read(staffListProvider.future);

      expect(staffRepository.listCallCount, greaterThan(staffCallsBefore));
    });

    test('failed mutation does not invalidate staffListProvider', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(clinicManagementProvider.future);
      await c.read(staffListProvider.future);
      final staffCallsBefore = staffRepository.listCallCount;

      branchRepository.createError = RpcFailure(const RpcResult(success: false, errorCode: 'DUPLICATE_CODE'));
      await c.read(clinicManagementProvider.notifier).addBranch(
        CreateBranchInput(name: 'East', workingSchedule: BranchWorkingSchedule.defaultSchedule()),
      );

      await c.read(staffListProvider.future);

      expect(staffRepository.listCallCount, staffCallsBefore);
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _TrackingOrganizationRepository implements OrganizationRepository {
  _TrackingOrganizationRepository({required this.profile});

  OrganizationProfile? profile;
  int fetchCallCount = 0;
  int updateCallCount = 0;
  Object? updateError;

  @override
  Future<OrganizationProfile?> fetchProfile({required String organizationId}) async {
    fetchCallCount++;
    return profile;
  }

  @override
  Future<String> updateOrganization(UpdateOrganizationInput input) async {
    updateCallCount++;
    if (updateError != null) {
      throw updateError!;
    }
    return profile?.id ?? orgIdFallback;
  }
}

const orgIdFallback = '00000000-0000-4000-8000-000000000020';

class _TrackingBranchRepository implements BranchRepository {
  _TrackingBranchRepository({required this.branches});

  List<BranchListItem> branches;
  int listCallCount = 0;
  int createCallCount = 0;
  int updateCallCount = 0;
  int deleteCallCount = 0;
  int setActiveCallCount = 0;
  Object? createError;
  Object? updateError;
  Object? deleteError;
  Object? setActiveError;

  @override
  Future<List<BranchListItem>> listBranches({
    required String organizationId,
    BranchListFilter filter = BranchListFilter.all,
  }) async {
    listCallCount++;
    return branches;
  }

  @override
  Future<String> createBranch(CreateBranchInput input) async {
    createCallCount++;
    if (createError != null) {
      throw createError!;
    }
    return 'new-branch-id';
  }

  @override
  Future<String> updateBranch(UpdateBranchInput input) async {
    updateCallCount++;
    if (updateError != null) {
      throw updateError!;
    }
    return input.branchId;
  }

  @override
  Future<RpcResult> deleteBranch({required String branchId}) async {
    deleteCallCount++;
    if (deleteError != null) {
      throw deleteError!;
    }
    return const RpcResult(success: true);
  }

  @override
  Future<RpcResult> setBranchActive({required String branchId, required bool isActive}) async {
    setActiveCallCount++;
    if (setActiveError != null) {
      throw setActiveError!;
    }
    return const RpcResult(success: true);
  }
}

class _TrackingStaffAdminRepository implements StaffAdminRepository {
  _TrackingStaffAdminRepository({required this.staff});

  List<StaffListItem> staff;
  int listCallCount = 0;
  int updateCallCount = 0;
  int deleteCallCount = 0;
  Object? updateError;
  Object? deleteError;

  @override
  Future<List<StaffListItem>> listStaff({StaffListFilter filter = StaffListFilter.all}) async {
    listCallCount++;
    return staff;
  }

  @override
  Future<StaffMemberDetail?> fetchStaffMember(String staffMemberId) => throw UnimplementedError();

  @override
  Future<String> updateStaffMember(UpdateStaffMemberInput input) async {
    updateCallCount++;
    if (updateError != null) {
      throw updateError!;
    }
    return input.staffMemberId;
  }

  @override
  Future<RpcResult> setStaffActive({required String staffMemberId, required bool isActive}) =>
      throw UnimplementedError();

  @override
  Future<RpcResult> deleteStaffMember({required String staffMemberId}) async {
    deleteCallCount++;
    if (deleteError != null) {
      throw deleteError!;
    }
    return const RpcResult(success: true);
  }
}

class _TrackingProvisioningRepository implements ProvisioningRepository {
  int createCallCount = 0;
  int resetPasswordCallCount = 0;
  int updateUsernameCallCount = 0;
  Object? createError;
  Object? resetPasswordError;
  Object? updateUsernameError;
  String? lastNewUsername;
  String? lastNewPassword;

  @override
  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input) async {
    createCallCount++;
    if (createError != null) {
      throw createError!;
    }
    return CreateStaffAccountResult(
      staffMemberId: '44444444-4444-4444-8444-444444444444',
      username: input.username,
      assignedPassword: input.password,
    );
  }

  @override
  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  }) async {
    resetPasswordCallCount++;
    lastNewPassword = newPassword;
    if (resetPasswordError != null) {
      throw resetPasswordError!;
    }
    return AdminResetStaffPasswordResult(staffMemberId: staffMemberId, assignedPassword: newPassword);
  }

  @override
  Future<AdminUpdateStaffUsernameResult> updateStaffUsername({
    required String staffMemberId,
    required String newUsername,
  }) async {
    updateUsernameCallCount++;
    lastNewUsername = newUsername;
    if (updateUsernameError != null) {
      throw updateUsernameError!;
    }
    return AdminUpdateStaffUsernameResult(staffMemberId: staffMemberId, username: newUsername);
  }

  @override
  Future<List<StaffMemberSummary>> listOrgStaffMembers() => throw UnimplementedError();

  @override
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds) => throw UnimplementedError();
}
