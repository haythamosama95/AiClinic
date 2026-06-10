/// ISO 4217 currency codes supported in clinic bootstrap (searchable dropdown).
abstract final class BootstrapCurrencyOptions {
  static const String defaultCode = 'EGP';

  static const List<String> codes = [
    'AED',
    'AUD',
    'BHD',
    'CAD',
    'CHF',
    'CNY',
    'EGP',
    'EUR',
    'GBP',
    'INR',
    'JOD',
    'JPY',
    'KWD',
    'OMR',
    'QAR',
    'SAR',
    'TRY',
    'USD',
    'ZAR',
  ];

  static List<String> filter(String query) {
    final normalized = query.trim().toUpperCase();
    if (normalized.isEmpty) {
      return codes;
    }
    return codes.where((code) => code.contains(normalized)).toList(growable: false);
  }

  static bool isValid(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    return codes.contains(value.trim().toUpperCase());
  }
}

/// IANA time zones for clinic bootstrap (searchable dropdown).
abstract final class BootstrapTimezoneOptions {
  static const String defaultZone = 'Africa/Cairo';

  static const List<String> zones = [
    'Africa/Cairo',
    'Africa/Johannesburg',
    'Africa/Lagos',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/New_York',
    'America/Toronto',
    'Asia/Baghdad',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Kuwait',
    'Asia/Qatar',
    'Asia/Riyadh',
    'Asia/Tokyo',
    'Australia/Sydney',
    'Europe/Berlin',
    'Europe/London',
    'Europe/Paris',
    'UTC',
  ];

  static List<String> filter(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return zones;
    }
    return zones.where((zone) => zone.toLowerCase().contains(normalized)).toList(growable: false);
  }

  static bool isValid(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return zones.any((zone) => zone.toLowerCase() == normalized);
  }
}
