import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_organization_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/clinic-management/presentation/models/staff_form_values.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';

@immutable
class ClinicManagementState {
  const ClinicManagementState({this.organization, this.branches = const [], this.staff = const []});

  final OrganizationProfile? organization;
  final List<BranchListItem> branches;
  final List<StaffListItem> staff;
}

/// Orchestrates organization, branches, and staff for the Clinic Management page.
///
/// Mirrors the web `useClinicManagementState` surface while delegating to RPC use cases.
final clinicManagementProvider = AsyncNotifierProvider<ClinicManagementNotifier, ClinicManagementState>(
  ClinicManagementNotifier.new,
);

class ClinicManagementNotifier extends AsyncNotifier<ClinicManagementState> {
  @override
  Future<ClinicManagementState> build() async {
    ref.watch(authSessionProvider.select((session) => session.context?.organizationId));
    return _load();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_load);
  }

  Future<void> updateOrganization(OrganizationProfile profile) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(updateOrganizationUseCaseProvider)(
        UpdateOrganizationInput(
          name: profile.name,
          logoUrl: profile.logoUrl,
          currencyCode: profile.currencyCode,
          timezone: profile.timezone,
          settingsJson: profile.settingsJson,
        ),
      );
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> addBranch(CreateBranchInput input) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(createBranchUseCaseProvider)(input);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> updateBranch(UpdateBranchInput input) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(updateBranchUseCaseProvider)(input);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> removeBranch(String branchId) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(deleteBranchUseCaseProvider)(branchId: branchId);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> toggleBranchActive({required String branchId, required bool isActive}) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(setBranchActiveUseCaseProvider)(branchId: branchId, isActive: isActive);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> addStaff(CreateStaffAccountInput input) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(createStaffAccountUseCaseProvider)(input);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> updateStaff(UpdateStaffMemberInput input) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(updateStaffMemberUseCaseProvider)(input);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  /// Updates staff profile fields and optional login credentials (web edit-mode parity).
  Future<void> updateStaffFromForm({
    required String staffMemberId,
    required StaffFormValues values,
    required String? originalUsername,
  }) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(updateStaffMemberUseCaseProvider)(toUpdateStaffMemberInput(staffMemberId, values));

      final trimmedUsername = values.username.trim();
      if (originalUsername != null && trimmedUsername != originalUsername) {
        await ref.read(updateStaffUsernameUseCaseProvider)(staffMemberId: staffMemberId, newUsername: trimmedUsername);
      }

      if (values.password.isNotEmpty) {
        await ref.read(resetStaffPasswordUseCaseProvider)(staffMemberId: staffMemberId, newPassword: values.password);
      }

      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<void> removeStaff(String staffMemberId) async {
    final previous = state.value;
    state = const AsyncLoading<ClinicManagementState>();
    state = await AsyncValue.guard(() async {
      await ref.read(deleteStaffMemberUseCaseProvider)(staffMemberId: staffMemberId);
      return _load();
    });
    if (state.hasError && previous != null) {
      state = AsyncData(previous);
    } else {
      _invalidateSiblingProviders();
    }
  }

  Future<ClinicManagementState> _load() async {
    final auth = ref.read(authSessionProvider);
    final organizationId = auth.context?.organizationId;

    OrganizationProfile? organization;
    var branches = const <BranchListItem>[];
    var staff = const <StaffListItem>[];

    if (organizationId != null && organizationId.isNotEmpty) {
      final canReadOrganization =
          AuthRouteGuard.canAccessOrganizationSettings(auth) || AuthRouteGuard.canAccessBranchManagement(auth);
      if (canReadOrganization) {
        organization = await ref.read(fetchOrganizationProfileUseCaseProvider)(organizationId: organizationId);
      }

      if (AuthRouteGuard.canAccessBranchManagement(auth)) {
        branches = await ref.read(listBranchesUseCaseProvider)(organizationId: organizationId);
      }
    }

    if (AuthRouteGuard.canAccessStaffManagement(auth)) {
      staff = await ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.all);
    }

    return ClinicManagementState(organization: organization, branches: branches, staff: staff);
  }

  void _invalidateSiblingProviders() {
    ref.invalidate(clinicSetupOrganizationProvider);
    ref.invalidate(clinicSetupBranchesProvider);
    ref.invalidate(staffListProvider);
  }
}
