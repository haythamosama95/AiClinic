/// Result of [admin_update_staff_username] RPC.
class AdminUpdateStaffUsernameResult {
  const AdminUpdateStaffUsernameResult({required this.staffMemberId, required this.username});

  final String staffMemberId;
  final String username;
}
