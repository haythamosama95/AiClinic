import 'package:ai_clinic/features/setup/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/setup/domain/admin_update_staff_username_result.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/staff_member_summary.dart';

/// Abstract staff provisioning operations (account creation, password reset).
abstract class ProvisioningRepository {
  Future<List<StaffMemberSummary>> listOrgStaffMembers();
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds);
  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input);
  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  });
  Future<AdminUpdateStaffUsernameResult> updateStaffUsername({
    required String staffMemberId,
    required String newUsername,
  });
}
