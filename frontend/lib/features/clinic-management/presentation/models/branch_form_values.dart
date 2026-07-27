import 'package:ai_clinic/core/domain/clinic/branch_list_item.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/create_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_branch_input.dart';
import 'package:ai_clinic/features/clinic-management/presentation/utils/working_schedule.dart';

/// Mutable branch form draft (web `BranchFormValues`).
class BranchFormValues {
  const BranchFormValues({
    required this.name,
    required this.code,
    required this.address,
    required this.phone,
    required this.mapsUrl,
    required this.workingSchedule,
  });

  final String name;
  final String code;
  final String address;
  final String phone;
  final String mapsUrl;
  final BranchWorkingSchedule workingSchedule;

  BranchFormValues copyWith({
    String? name,
    String? code,
    String? address,
    String? phone,
    String? mapsUrl,
    BranchWorkingSchedule? workingSchedule,
  }) {
    return BranchFormValues(
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      workingSchedule: workingSchedule ?? this.workingSchedule,
    );
  }
}

BranchFormValues emptyBranchFormValues() {
  return BranchFormValues(
    name: '',
    code: '',
    address: '',
    phone: '',
    mapsUrl: '',
    workingSchedule: emptyWorkingSchedule(),
  );
}

BranchFormValues branchToFormValues(BranchListItem branch) {
  return BranchFormValues(
    name: branch.name,
    code: branch.code ?? '',
    address: branch.address ?? '',
    phone: branch.phone ?? '',
    mapsUrl: branch.mapsUrl ?? '',
    workingSchedule: branch.workingSchedule ?? emptyWorkingSchedule(),
  );
}

typedef BranchFormErrors = Map<String, String>;

String? _validatePhone(String phone) {
  if (phone.trim().isEmpty) {
    return 'Phone is required';
  }
  if (!RegExp(r'^\d+$').hasMatch(phone)) {
    return 'Phone must contain numbers only';
  }
  return null;
}

String? _validateMapsUrl(String url) {
  if (url.trim().isEmpty) {
    return 'Maps URL is required';
  }
  final normalized = url.trim().startsWith(RegExp('http', caseSensitive: false))
      ? url.trim()
      : 'https://${url.trim()}';
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return 'Enter a valid URL';
  }
  return null;
}

BranchFormErrors validateBranch(BranchFormValues values, {required bool requireHours}) {
  final errors = <String, String>{};
  if (values.name.trim().isEmpty) {
    errors['name'] = 'Branch name is required';
  }
  if (values.code.trim().isEmpty) {
    errors['code'] = 'Branch code is required';
  }
  if (values.address.trim().isEmpty) {
    errors['address'] = 'Address is required';
  }
  final phoneError = _validatePhone(values.phone);
  if (phoneError != null) {
    errors['phone'] = phoneError;
  }
  final mapsError = _validateMapsUrl(values.mapsUrl);
  if (mapsError != null) {
    errors['mapsUrl'] = mapsError;
  }
  if (requireHours && !hasConfiguredWorkingHours(values.workingSchedule)) {
    errors['workingSchedule'] = 'Working hours are required';
  }
  return errors;
}

String? _optionalTrimmed(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

CreateBranchInput createBranchInputFromFormValues(BranchFormValues values) {
  return CreateBranchInput(
    name: values.name.trim(),
    workingSchedule: values.workingSchedule,
    code: _optionalTrimmed(values.code),
    address: _optionalTrimmed(values.address),
    phone: values.phone.trim(),
    mapsUrl: values.mapsUrl.trim(),
  );
}

UpdateBranchInput updateBranchInputFromFormValues({
  required String branchId,
  required BranchFormValues values,
}) {
  return UpdateBranchInput(
    branchId: branchId,
    name: values.name.trim(),
    workingSchedule: values.workingSchedule,
    code: _optionalTrimmed(values.code),
    address: _optionalTrimmed(values.address),
    phone: values.phone.trim(),
    mapsUrl: values.mapsUrl.trim(),
  );
}
