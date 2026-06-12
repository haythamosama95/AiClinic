import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Input for `create_staff_account` RPC.
class CreateStaffAccountInput {
  const CreateStaffAccountInput({
    required this.username,
    required this.password,
    required this.fullName,
    required this.role,
    required this.branchIds,
    this.primaryBranchId,
    this.phone,
  });

  final String username;
  final String password;
  final String fullName;
  final StaffRole role;
  final List<String> branchIds;
  final String? primaryBranchId;
  final String? phone;
}
