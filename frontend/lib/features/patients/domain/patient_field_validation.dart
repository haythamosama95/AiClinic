/// Client-side validation for patient registration fields.
abstract final class PatientFieldValidation {
  static final _digitsOnly = RegExp(r'^\d+$');

  /// Returns a validation error kind, or null when valid.
  static MobileNumberValidationError? validateMobileNumber(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return MobileNumberValidationError.required;
    }
    final trimmed = raw.trim();
    if (!_digitsOnly.hasMatch(trimmed)) {
      return MobileNumberValidationError.digitsOnly;
    }
    if (trimmed.length < 8 || trimmed.length > 15) {
      return MobileNumberValidationError.invalidLength;
    }
    return null;
  }
}

enum MobileNumberValidationError {
  required,
  digitsOnly,
  invalidLength,
}
