import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_result.dart';
import 'package:ai_clinic/features/setup/domain/repositories/provisioning_repository.dart';

class CreateStaffAccount {
  const CreateStaffAccount(this._repository);
  final ProvisioningRepository _repository;

  Future<CreateStaffAccountResult> call(CreateStaffAccountInput input) {
    return _repository.createStaffAccount(input);
  }
}
