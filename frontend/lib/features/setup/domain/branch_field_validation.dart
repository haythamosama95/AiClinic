/// Client-side validation for branch setup fields.
abstract final class BranchFieldValidation {
  static const nationalPhoneLength = 10;
  static const branchCodeMaxLength = 20;

  static final _digitsOnly = RegExp(r'^\d+$');
  static final _branchCodePattern = RegExp(r'^[A-Z0-9]+$');

  /// Returns a user-facing validation message, or null when valid.
  static String? validatePhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Phone is required';
    }
    if (!_digitsOnly.hasMatch(raw.trim())) {
      return 'Phone must contain numbers only';
    }
    return null;
  }

  /// Validates a national mobile number entered via [AppPhoneInput] (10 digits).
  static String? validateNationalPhone(String? raw) {
    final baseError = validatePhone(raw);
    if (baseError != null) {
      return baseError;
    }
    if (raw!.trim().length != nationalPhoneLength) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  /// Returns a user-facing validation message, or null when valid.
  static String? validateBranchCode(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Branch code is required';
    }
    final normalized = trimmed.toUpperCase();
    if (normalized.length > branchCodeMaxLength) {
      return 'Branch code must be $branchCodeMaxLength characters or fewer';
    }
    if (!_branchCodePattern.hasMatch(normalized)) {
      return 'Use letters and numbers only';
    }
    return null;
  }

  static bool isValidPhone(String raw) => validatePhone(raw) == null;

  static bool isValidNationalPhone(String raw) => validateNationalPhone(raw) == null;

  /// Returns a user-facing validation message, or null when valid.
  static String? validateMapsUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'Maps URL is required';
    }
    if (!isValidMapsUrl(raw)) {
      return 'Enter a valid website or maps link';
    }
    return null;
  }

  /// Accepts absolute http(s) URLs and bare domains such as `www.google.com`.
  static bool isValidMapsUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final Uri? uri;
    if (trimmed.contains('://')) {
      uri = Uri.tryParse(trimmed);
      if (uri == null || uri.host.isEmpty) {
        return false;
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }
    } else {
      uri = Uri.tryParse('https://$trimmed');
      if (uri == null || uri.host.isEmpty) {
        return false;
      }
    }

    return _isPlausibleHost(uri.host);
  }

  static bool _isPlausibleHost(String host) {
    if (host.contains(' ')) {
      return false;
    }
    return host.contains('.');
  }
}
