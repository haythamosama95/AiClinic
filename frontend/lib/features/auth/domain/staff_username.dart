/// Normalizes and validates clinic staff usernames (stored in GoTrue `auth.users.email`).
String normalizeStaffUsername(String raw) => raw.trim().toLowerCase();

/// Hint shown below the username field in staff forms.
const staffUsernameRequirements =
    '3–32 characters. Letters, numbers, underscore, and hyphen. Must start and end with a letter or number.';

/// Returns a user-facing validation message, or null when valid.
String? validateStaffUsername(String raw) {
  final normalized = normalizeStaffUsername(raw);
  if (normalized.isEmpty) {
    return 'Username is required.';
  }
  if (normalized.contains('@')) {
    return 'Enter a valid username.';
  }
  if (normalized.length < 3 || normalized.length > 32) {
    return 'Enter a valid username.';
  }
  final validPattern = RegExp(r'^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$');
  if (!validPattern.hasMatch(normalized)) {
    return 'Username may use letters, numbers, underscore, and hyphen.';
  }
  return null;
}
