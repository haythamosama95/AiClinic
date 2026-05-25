/// Successful administrator password reset payload.
class AdminResetStaffPasswordResult {
  const AdminResetStaffPasswordResult({required this.staffMemberId, required this.assignedPassword});

  final String staffMemberId;
  final String assignedPassword;
}
