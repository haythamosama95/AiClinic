/// Client-side validation for branch setup fields.
abstract final class BranchFieldValidation {
  static final _digitsOnly = RegExp(r'^\d+$');

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

  static bool isValidPhone(String raw) => validatePhone(raw) == null;

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
