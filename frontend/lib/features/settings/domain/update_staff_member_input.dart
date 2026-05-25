import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Input for [update_staff_member] RPC.
class UpdateStaffMemberInput {
  const UpdateStaffMemberInput({
    required this.staffMemberId,
    required this.fullName,
    required this.role,
    required this.branchIds,
    this.phone,
    this.primaryBranchId,
    this.isActive,
  });

  final String staffMemberId;
  final String fullName;
  final StaffRole role;
  final List<String> branchIds;
  final String? phone;
  final String? primaryBranchId;
  final bool? isActive;
}
