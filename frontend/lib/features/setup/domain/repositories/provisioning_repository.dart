import 'package:ai_clinic/features/auth/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/auth/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/auth/domain/staff_member_summary.dart';

/// Abstract staff provisioning operations (account creation, password reset).
abstract class ProvisioningRepository {
  Future<List<StaffMemberSummary>> listOrgStaffMembers();
  Future<List<BranchSummary>> listBranchesByIds(List<String> branchIds);
  Future<CreateStaffAccountResult> createStaffAccount(CreateStaffAccountInput input);
  Future<AdminResetStaffPasswordResult> resetStaffPassword({
    required String staffMemberId,
    required String newPassword,
  });
}
