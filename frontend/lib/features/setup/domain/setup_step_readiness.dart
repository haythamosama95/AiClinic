import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

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

/// Whether the branch wizard text fields are valid (excluding working hours).
bool isBranchStepFieldsReady({
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

/// Whether the branch wizard step has enough valid input to continue.
bool isBranchStepReady({
  required String name,
  required String code,
  required String address,
  required String phone,
  required String mapsUrl,
  required BranchWorkingSchedule workingSchedule,
}) {
  if (!isBranchStepFieldsReady(name: name, code: code, address: address, phone: phone, mapsUrl: mapsUrl)) {
    return false;
  }
  if (!workingSchedule.hasConfiguredWorkingHours) {
    return false;
  }
  return true;
}
