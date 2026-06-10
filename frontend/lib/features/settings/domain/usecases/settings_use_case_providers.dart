import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/settings/data/branch_repository.dart';
import 'package:ai_clinic/features/settings/data/organization_repository.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_branches.dart';
import 'package:ai_clinic/features/settings/domain/usecases/create_branch.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_branch.dart';
import 'package:ai_clinic/features/settings/domain/usecases/set_branch_active.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_organization_profile.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_organization.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_permission_matrix.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_role_permission.dart';
import 'package:ai_clinic/features/settings/domain/usecases/list_staff.dart';
import 'package:ai_clinic/features/settings/domain/usecases/fetch_staff_member.dart';
import 'package:ai_clinic/features/settings/domain/usecases/update_staff_member.dart';
import 'package:ai_clinic/features/settings/domain/usecases/set_staff_active.dart';

final listBranchesUseCaseProvider = Provider((ref) => ListBranches(ref.watch(branchRepositoryProvider)));
final createBranchUseCaseProvider = Provider((ref) => CreateBranch(ref.watch(branchRepositoryProvider)));
final updateBranchUseCaseProvider = Provider((ref) => UpdateBranch(ref.watch(branchRepositoryProvider)));
final setBranchActiveUseCaseProvider = Provider((ref) => SetBranchActive(ref.watch(branchRepositoryProvider)));
final fetchOrganizationProfileUseCaseProvider = Provider(
  (ref) => FetchOrganizationProfile(ref.watch(organizationRepositoryProvider)),
);
final updateOrganizationUseCaseProvider = Provider(
  (ref) => UpdateOrganization(ref.watch(organizationRepositoryProvider)),
);
final fetchPermissionMatrixUseCaseProvider = Provider(
  (ref) => FetchPermissionMatrix(ref.watch(rolePermissionsRepositoryProvider)),
);
final updateRolePermissionUseCaseProvider = Provider(
  (ref) => UpdateRolePermission(ref.watch(rolePermissionsRepositoryProvider)),
);
final listStaffUseCaseProvider = Provider((ref) => ListStaff(ref.watch(staffAdminRepositoryProvider)));
final fetchStaffMemberUseCaseProvider = Provider((ref) => FetchStaffMember(ref.watch(staffAdminRepositoryProvider)));
final updateStaffMemberUseCaseProvider = Provider((ref) => UpdateStaffMember(ref.watch(staffAdminRepositoryProvider)));
final setStaffActiveUseCaseProvider = Provider((ref) => SetStaffActive(ref.watch(staffAdminRepositoryProvider)));
