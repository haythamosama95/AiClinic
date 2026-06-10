import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/domain/usecases/create_bootstrap_branch.dart';
import 'package:ai_clinic/features/setup/domain/usecases/create_organization.dart';
import 'package:ai_clinic/features/setup/domain/usecases/create_staff_account.dart';
import 'package:ai_clinic/features/setup/domain/usecases/list_branches_by_ids.dart';
import 'package:ai_clinic/features/setup/domain/usecases/list_org_staff_members.dart';
import 'package:ai_clinic/features/setup/domain/usecases/reset_installation.dart';
import 'package:ai_clinic/features/setup/domain/usecases/reset_staff_password.dart';

final createOrganizationUseCaseProvider = Provider((ref) => CreateOrganization(ref.watch(bootstrapRepositoryProvider)));
final createBootstrapBranchUseCaseProvider = Provider(
  (ref) => CreateBootstrapBranch(ref.watch(bootstrapRepositoryProvider)),
);
final resetInstallationUseCaseProvider = Provider((ref) => ResetInstallation(ref.watch(bootstrapRepositoryProvider)));
final listOrgStaffMembersUseCaseProvider = Provider(
  (ref) => ListOrgStaffMembers(ref.watch(provisioningRepositoryProvider)),
);
final listBranchesByIdsUseCaseProvider = Provider(
  (ref) => ListBranchesByIds(ref.watch(provisioningRepositoryProvider)),
);
final createStaffAccountUseCaseProvider = Provider(
  (ref) => CreateStaffAccount(ref.watch(provisioningRepositoryProvider)),
);
final resetStaffPasswordUseCaseProvider = Provider(
  (ref) => ResetStaffPassword(ref.watch(provisioningRepositoryProvider)),
);
