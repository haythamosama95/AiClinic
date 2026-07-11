import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/patients/domain/patient_field_validation.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';

@immutable
class PatientFormErrors {
  const PatientFormErrors({
    this.fullName,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.notes,
    this.form,
  });

  static const empty = PatientFormErrors();

  final String? fullName;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? maritalStatus;
  final String? notes;

  /// RPC or form-level error (`_form` in the web reference).
  final String? form;

  bool get hasErrors =>
      fullName != null ||
      phone != null ||
      dateOfBirth != null ||
      gender != null ||
      maritalStatus != null ||
      notes != null ||
      form != null;

  PatientFormErrors copyWith({
    String? fullName,
    String? phone,
    String? dateOfBirth,
    String? gender,
    String? maritalStatus,
    String? notes,
    String? form,
    bool clearFullName = false,
    bool clearPhone = false,
    bool clearDateOfBirth = false,
    bool clearGender = false,
    bool clearMaritalStatus = false,
    bool clearNotes = false,
    bool clearForm = false,
  }) {
    return PatientFormErrors(
      fullName: clearFullName ? null : (fullName ?? this.fullName),
      phone: clearPhone ? null : (phone ?? this.phone),
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      gender: clearGender ? null : (gender ?? this.gender),
      maritalStatus: clearMaritalStatus ? null : (maritalStatus ?? this.maritalStatus),
      notes: clearNotes ? null : (notes ?? this.notes),
      form: clearForm ? null : (form ?? this.form),
    );
  }
}

@immutable
class PatientRegistrationForm {
  const PatientRegistrationForm({
    this.fullName = '',
    this.phone = '',
    this.dateOfBirth,
    this.gender,
    this.maritalStatus,
    this.notes = '',
  });

  static const empty = PatientRegistrationForm();

  final String fullName;
  final String phone;
  final DateTime? dateOfBirth;
  final PatientGender? gender;
  final PatientMaritalStatus? maritalStatus;
  final String notes;

  PatientRegistrationForm copyWith({
    String? fullName,
    String? phone,
    Object? dateOfBirth = _sentinel,
    Object? gender = _sentinel,
    Object? maritalStatus = _sentinel,
    String? notes,
  }) {
    return PatientRegistrationForm(
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      dateOfBirth: identical(dateOfBirth, _sentinel) ? this.dateOfBirth : dateOfBirth as DateTime?,
      gender: identical(gender, _sentinel) ? this.gender : gender as PatientGender?,
      maritalStatus: identical(maritalStatus, _sentinel) ? this.maritalStatus : maritalStatus as PatientMaritalStatus?,
      notes: notes ?? this.notes,
    );
  }
}

const _sentinel = Object();

PatientFormErrors validateRegistration(PatientRegistrationForm form) {
  String? fullNameError;
  final name = form.fullName.trim();
  if (name.isEmpty) {
    fullNameError = "Enter the patient's full name.";
  } else if (name.length < 2) {
    fullNameError = 'Full name must be at least 2 characters.';
  }

  final phoneError = PatientFieldValidation.validateMobileNumber(form.phone);

  return PatientFormErrors(
    fullName: fullNameError,
    phone: phoneError,
  );
}
