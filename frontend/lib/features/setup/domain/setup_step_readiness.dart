import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';

/// Whether the organization wizard step has enough valid input to continue.
bool isOrganizationStepReady({required String name, required String? currency, required String? timezone}) {
  if (name.trim().isEmpty) {
    return false;
  }
  if (!BootstrapCurrencyOptions.isValid(currency)) {
    return false;
  }
  if (!BootstrapTimezoneOptions.isValid(timezone)) {
    return false;
  }
  return true;
}

/// Whether the branch wizard step has enough valid input to continue.
bool isBranchStepReady({
  required String name,
  required String code,
  required String address,
  required String phone,
  required String mapsUrl,
}) {
  if (name.trim().isEmpty) {
    return false;
  }
  if (code.trim().isEmpty) {
    return false;
  }
  if (address.trim().isEmpty) {
    return false;
  }
  if (!BranchFieldValidation.isValidPhone(phone)) {
    return false;
  }
  if (!BranchFieldValidation.isValidMapsUrl(mapsUrl)) {
    return false;
  }
  return true;
}
