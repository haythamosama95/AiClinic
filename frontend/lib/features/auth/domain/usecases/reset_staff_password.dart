import 'package:ai_clinic/features/auth/domain/admin_reset_staff_password_result.dart';
import 'package:ai_clinic/features/auth/domain/repositories/provisioning_repository.dart';

class ResetStaffPassword {
  const ResetStaffPassword(this._repository);
  final ProvisioningRepository _repository;

  Future<AdminResetStaffPasswordResult> call({
    required String staffMemberId,
    required String newPassword,
  }) {
    return _repository.resetStaffPassword(
      staffMemberId: staffMemberId,
      newPassword: newPassword,
    );
  }
}
