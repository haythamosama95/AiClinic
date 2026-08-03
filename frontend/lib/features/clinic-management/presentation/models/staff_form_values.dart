import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart';
import 'package:ai_clinic/features/setup/domain/create_staff_account_input.dart';
import 'package:flutter/foundation.dart';

enum StaffFormMode { create, edit }

@immutable
class StaffFormValues {
  const StaffFormValues({
    this.fullName = '',
    this.phone = '',
    this.username = '',
    this.password = '',
    this.role,
    this.branchIds = const [],
    this.primaryBranchId,
  });

  final String fullName;
  final String phone;
  final String username;
  final String password;
  final StaffRole? role;
  final List<String> branchIds;
  final String? primaryBranchId;

  StaffFormValues copyWith({
    String? fullName,
    String? phone,
    String? username,
    String? password,
    StaffRole? role,
    List<String>? branchIds,
    String? primaryBranchId,
    bool clearPrimaryBranchId = false,
  }) {
    return StaffFormValues(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      branchIds: branchIds ?? this.branchIds,
      primaryBranchId: clearPrimaryBranchId ? null : (primaryBranchId ?? this.primaryBranchId),
    );
  }
}

typedef StaffFormErrors = Map<String, String>;

StaffFormValues emptyStaffFormValues() => const StaffFormValues();

StaffFormValues staffToFormValues(StaffListItem staff) {
  final branchIds = [
    for (final branch in staff.branches)
      if (branch.id != null && branch.id!.isNotEmpty) branch.id!,
  ];
  final primaryBranchId =
      staff.branches.where((branch) => branch.isPrimary).map((branch) => branch.id).whereType<String>().firstOrNull ??
      (branchIds.length == 1 ? branchIds.first : null);

  return StaffFormValues(
    fullName: staff.fullName,
    phone: staff.phone ?? '',
    username: staff.username ?? '',
    password: '',
    role: staff.role,
    branchIds: branchIds,
    primaryBranchId: primaryBranchId,
  );
}

String? _validateUsername(String username) {
  if (username.trim().isEmpty) {
    return 'Username is required';
  }
  if (username.length < 3 || username.length > 32) {
    return 'Username must be 3–32 characters';
  }
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]*$').hasMatch(username)) {
    return 'Username format is invalid';
  }
  return null;
}

String? _validatePassword(String password, {required bool required}) {
  if (password.isEmpty) {
    return required ? 'Password is required' : null;
  }
  if (password.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Password must include an uppercase letter';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Password must include a lowercase letter';
  }
  if (!RegExp(r'\d').hasMatch(password)) {
    return 'Password must include a number';
  }
  return null;
}

StaffFormErrors validateStaff(StaffFormValues values, StaffFormMode mode) {
  return _validateStaff(values, isCreate: mode == StaffFormMode.create);
}

StaffFormErrors _validateStaff(StaffFormValues values, {required bool isCreate}) {
  final errors = <String, String>{};

  if (values.fullName.trim().isEmpty) {
    errors['fullName'] = 'Full name is required';
  }

  if (isCreate) {
    if (values.phone.trim().isEmpty) {
      errors['phone'] = 'Phone is required';
    } else if (!RegExp(r'^\d+$').hasMatch(values.phone)) {
      errors['phone'] = 'Phone must contain numbers only';
    }
  } else if (values.phone.isNotEmpty && !RegExp(r'^\d+$').hasMatch(values.phone)) {
    errors['phone'] = 'Phone must contain numbers only';
  }

  final usernameError = _validateUsername(values.username);
  if (usernameError != null) {
    errors['username'] = usernameError;
  }

  final passwordError = _validatePassword(values.password, required: isCreate);
  if (passwordError != null) {
    errors['password'] = passwordError;
  }

  if (values.role == null) {
    errors['role'] = 'Select a role';
  }

  if (values.branchIds.isEmpty) {
    errors['branchIds'] = 'Select at least one branch assignment';
  }

  return errors;
}

CreateStaffAccountInput toCreateStaffAccountInput(StaffFormValues values) {
  return CreateStaffAccountInput(
    username: values.username.trim(),
    password: values.password,
    fullName: values.fullName.trim(),
    role: values.role!,
    branchIds: values.branchIds,
    primaryBranchId: values.primaryBranchId,
    phone: values.phone.trim().isEmpty ? null : values.phone.trim(),
  );
}

UpdateStaffMemberInput toUpdateStaffMemberInput(String staffMemberId, StaffFormValues values) {
  return UpdateStaffMemberInput(
    staffMemberId: staffMemberId,
    fullName: values.fullName.trim(),
    role: values.role!,
    branchIds: values.branchIds,
    primaryBranchId: values.primaryBranchId,
    phone: values.phone.trim().isEmpty ? null : values.phone.trim(),
  );
}
