/// Successful administrator password reset payload.
class AdminResetStaffPasswordResult {
  AdminResetStaffPasswordResult({required this.staffMemberId, required String assignedPassword})
    : _assignedPassword = assignedPassword;

  final String staffMemberId;

  String? _assignedPassword;
  bool _assignedPasswordRevealed = false;

  /// Returns the assigned password once for display; later calls return null.
  String? revealAssignedPassword() {
    if (_assignedPasswordRevealed) {
      return null;
    }
    _assignedPasswordRevealed = true;
    return _assignedPassword;
  }

  /// Clears the assigned password from memory after it has been shown.
  void clearAssignedPassword() {
    _assignedPassword = null;
    _assignedPasswordRevealed = true;
  }

  @override
  String toString() => 'AdminResetStaffPasswordResult(staffMemberId: $staffMemberId)';
}
