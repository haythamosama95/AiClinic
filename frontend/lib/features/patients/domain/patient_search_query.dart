/// Client-side validation for patient list search (V1-3).
abstract final class PatientSearchQuery {
  static final _digitsOnly = RegExp(r'^\d+$');

  static bool isPhonePrefixQuery(String query) => _digitsOnly.hasMatch(query.trim());

  /// Returns a user hint when [query] is too short to search; `null` when valid or browse mode.
  static String? validationHint(String? query) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    if (isPhonePrefixQuery(trimmed)) {
      if (trimmed.length < 2) {
        return 'Enter at least 2 digits to search by phone.';
      }
      return null;
    }

    if (trimmed.length < 3) {
      return 'Enter at least 3 characters to search by name.';
    }

    return null;
  }

  /// Whether the query can be sent to `search_patients` (empty = browse).
  static bool canInvokeRpc(String? query) => validationHint(query) == null;

  static String helperForDraft(String? query) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Browse all patients in scope, or search by name (3+ letters) or phone prefix (2+ digits).';
    }
    if (isPhonePrefixQuery(trimmed)) {
      return 'Phone prefix search — enter at least 2 digits.';
    }
    return 'Name search — enter at least 3 characters.';
  }
}
