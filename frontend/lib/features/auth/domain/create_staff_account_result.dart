/// Successful staff account creation payload.
class CreateStaffAccountResult {
  const CreateStaffAccountResult({required this.staffMemberId, required this.username, required this.assignedPassword});

  final String staffMemberId;
  final String username;
  final String assignedPassword;
}
