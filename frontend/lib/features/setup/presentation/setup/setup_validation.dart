import 'package:ai_clinic/features/auth/domain/staff_username.dart';
import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/domain/branch_field_validation.dart';
import 'package:ai_clinic/features/setup/domain/staff_password_validation.dart';

typedef StepErrors = Map<String, String>;

Map<String, String> validateOrganization(OrganizationDraft org) {
  final errors = <String, String>{};
  if (org.name.trim().isEmpty) {
    errors['name'] = 'Organization name is required';
  }
  if (org.timezone.isEmpty) {
    errors['timezone'] = 'Select a timezone';
  }
  if (org.currency.isEmpty) {
    errors['currency'] = 'Select a currency';
  }
  return errors;
}

Map<String, String> validateBranches(List<BranchDraft> branches) {
  final errors = <String, String>{};
  if (branches.isEmpty) {
    errors['_form'] = 'Add at least one branch';
    return errors;
  }

  for (var index = 0; index < branches.length; index++) {
    errors.addAll(validateSingleBranch(branches[index], index, allBranches: branches));
  }

  return errors;
}

Map<String, String> validateSingleBranch(BranchDraft branch, int index, {List<BranchDraft>? allBranches}) {
  final errors = <String, String>{};
  final prefix = 'branch-$index';

  if (branch.name.trim().isEmpty) {
    errors['$prefix-name'] = 'Branch name is required';
  }

  final codeError = BranchFieldValidation.validateBranchCode(branch.code);
  if (codeError != null) {
    errors['$prefix-code'] = codeError;
  } else if (allBranches != null) {
    final normalizedCode = branch.code.trim().toUpperCase();
    for (var otherIndex = 0; otherIndex < allBranches.length; otherIndex++) {
      if (otherIndex == index) continue;
      if (allBranches[otherIndex].code.trim().toUpperCase() == normalizedCode) {
        errors['$prefix-code'] = 'Branch code must be unique';
        break;
      }
    }
  }

  final mobileError = BranchFieldValidation.validateNationalPhone(branch.mobile);
  if (mobileError != null) {
    errors['$prefix-mobile'] = mobileError;
  }

  final mapError = BranchFieldValidation.validateMapsUrl(branch.mapLocation);
  if (mapError != null) {
    errors['$prefix-map'] = mapError;
  }

  final hasOpenDay = branch.workingDays.any((day) => day.enabled);
  if (!hasOpenDay) {
    errors['$prefix-hours'] = 'Enable at least one working day';
  }

  for (final day in branch.workingDays) {
    if (!day.enabled) continue;
    if (day.openTime.compareTo(day.closeTime) >= 0) {
      errors['$prefix-${day.day}-time'] = 'Closing time must be after opening';
    }
  }

  return errors;
}

Map<String, String> validateSingleStaff(
  StaffDraft member,
  int index, {
  List<StaffDraft>? allStaff,
  int branchCount = 1,
}) {
  final errors = <String, String>{};
  final prefix = 'staff-$index';

  if (member.name.trim().isEmpty) {
    errors['$prefix-name'] = 'Name is required';
  }

  final mobileError = BranchFieldValidation.validateNationalPhone(member.mobile);
  if (mobileError != null) {
    errors['$prefix-mobile'] = mobileError;
  }

  final usernameError = validateStaffUsername(member.username);
  if (usernameError != null) {
    errors['$prefix-username'] = usernameError;
  } else if (allStaff != null) {
    final normalizedUsername = normalizeStaffUsername(member.username);
    for (var otherIndex = 0; otherIndex < allStaff.length; otherIndex++) {
      if (otherIndex == index) continue;
      if (normalizeStaffUsername(allStaff[otherIndex].username) == normalizedUsername) {
        errors['$prefix-username'] = 'Usernames must be unique';
        break;
      }
    }
  }

  final passwordError = StaffPasswordValidation.validateInitialPassword(member.password);
  if (passwordError != null) {
    errors['$prefix-password'] = passwordError;
  }

  if (member.role.isEmpty) {
    errors['$prefix-role'] = 'Select a role';
  }
  if (branchCount > 0 && member.branchIds.isEmpty) {
    errors['$prefix-branches'] = 'Assign at least one branch';
  }

  return errors;
}

Map<String, String> validateStaff(List<StaffDraft> staff, int branchCount) {
  final errors = <String, String>{};
  if (staff.isEmpty) {
    errors['_form'] = 'Add at least one staff member';
    return errors;
  }

  for (var index = 0; index < staff.length; index++) {
    errors.addAll(validateSingleStaff(staff[index], index, allStaff: staff, branchCount: branchCount));
  }

  return errors;
}

Map<String, String> validateSingleService(ServiceDraft service, int index, {List<ServiceDraft>? allServices}) {
  final errors = <String, String>{};
  final prefix = 'service-$index';

  final nameError = ServiceFormValidation.validateName(service.name);
  if (nameError != null) {
    errors['$prefix-name'] = nameError;
  } else if (allServices != null) {
    final normalizedName = service.name.trim().toLowerCase();
    for (var otherIndex = 0; otherIndex < allServices.length; otherIndex++) {
      if (otherIndex == index) continue;
      if (allServices[otherIndex].name.trim().toLowerCase() == normalizedName) {
        errors['$prefix-name'] = 'Service names must be unique';
        break;
      }
    }
  }

  final priceError = _validateServicePrice(service.price);
  if (priceError != null) {
    errors['$prefix-price'] = priceError;
  }

  return errors;
}

Map<String, String> validateServices(List<ServiceDraft> services) {
  final errors = <String, String>{};
  if (services.isEmpty) {
    errors['_form'] = 'Add at least one service';
    return errors;
  }

  for (var index = 0; index < services.length; index++) {
    errors.addAll(validateSingleService(services[index], index, allServices: services));
  }

  return errors;
}

String? _validateServicePrice(double? price) {
  if (price == null || price.isNaN || price.isInfinite) {
    return 'Enter a valid price';
  }
  if (price < 0) {
    return 'Price must be zero or greater';
  }
  final cents = (price * 100).round();
  if ((cents / 100 - price).abs() > 0.001) {
    return 'Enter a valid price with at most two decimal places';
  }
  return null;
}

bool hasErrors(Map<String, String> errors) => errors.isNotEmpty;

Set<String> confirmedBranchIdsForSetup(List<BranchDraft> branches) {
  final confirmed = <String>{};
  for (var index = 0; index < branches.length; index++) {
    final branchErrors = validateSingleBranch(branches[index], index, allBranches: branches);
    if (!hasErrors(branchErrors)) {
      confirmed.add(branches[index].id);
    }
  }
  return confirmed;
}

Set<String> confirmedStaffIdsForSetup(List<StaffDraft> staff, int branchCount) {
  final confirmed = <String>{};
  for (var index = 0; index < staff.length; index++) {
    final memberErrors = validateSingleStaff(staff[index], index, allStaff: staff, branchCount: branchCount);
    if (!hasErrors(memberErrors)) {
      confirmed.add(staff[index].id);
    }
  }
  return confirmed;
}

Set<String> confirmedServiceIdsForSetup(List<ServiceDraft> services) {
  final confirmed = <String>{};
  for (var index = 0; index < services.length; index++) {
    final serviceErrors = validateSingleService(services[index], index, allServices: services);
    if (!hasErrors(serviceErrors)) {
      confirmed.add(services[index].id);
    }
  }
  return confirmed;
}

Map<String, String> validateStep(int step, SetupDraft draft) {
  switch (step) {
    case 0:
      return validateOrganization(draft.organization);
    case 1:
      return validateBranches(draft.branches);
    case 2:
      return validateStaff(draft.staff, draft.branches.length);
    case 3:
      return validateServices(draft.services);
    default:
      return {};
  }
}
