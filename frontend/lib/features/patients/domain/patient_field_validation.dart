/// Client-side validation for patient registration fields.
abstract final class PatientFieldValidation {
  static final _digitsOnly = RegExp(r'^\d+$');

  /// Returns a user-facing validation message, or null when valid.
  static String? validateMobileNumber(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Mobile number is required.';
    }
    final trimmed = raw.trim();
    if (!_digitsOnly.hasMatch(trimmed)) {
      return 'Only numbers are allowed.';
    }
    if (trimmed.length < 8 || trimmed.length > 15) {
      return 'Mobile number must be 8 to 15 digits.';
    }
    return null;
  }
}
