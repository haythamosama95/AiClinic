/// Client-side validation for staff initial passwords (matches backend complexity rules).
abstract final class StaffPasswordValidation {
  /// Hint shown below the initial password field in staff forms.
  static const initialPasswordRequirements = 'At least 8 characters with one letter.';

  static final _hasLetter = RegExp(r'[A-Za-z]');

  /// Returns a user-facing validation message, or null when valid.
  static String? validateInitialPassword(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'Password is required';
    }
    if (raw.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!_hasLetter.hasMatch(raw)) {
      return 'Password must contain at least one letter';
    }
    return null;
  }
}
