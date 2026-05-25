import 'package:flutter/foundation.dart';

/// Organization row for steady-state settings (V1-2).
@immutable
class OrganizationProfile {
  const OrganizationProfile({
    required this.id,
    required this.name,
    this.logoUrl,
    this.currencyCode,
    this.timezone,
    this.settingsJson,
    this.subscriptionTier,
    this.subscriptionValidUntil,
  });

  final String id;
  final String name;
  final String? logoUrl;
  final String? currencyCode;
  final String? timezone;
  final Map<String, dynamic>? settingsJson;
  final String? subscriptionTier;
  final DateTime? subscriptionValidUntil;

  static OrganizationProfile? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final name = row['name']?.toString().trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) {
      return null;
    }

    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    Map<String, dynamic>? parseSettingsJson(Object? value) {
      if (value == null) {
        return null;
      }
      if (value is Map<String, dynamic>) {
        return Map<String, dynamic>.from(value);
      }
      if (value is Map) {
        return value.map((key, dynamic v) => MapEntry(key.toString(), v));
      }
      return null;
    }

    DateTime? parseSubscriptionUntil(Object? value) {
      if (value == null) {
        return null;
      }
      if (value is DateTime) {
        return value;
      }
      final text = value.toString().trim();
      if (text.isEmpty) {
        return null;
      }
      return DateTime.tryParse(text);
    }

    return OrganizationProfile(
      id: id,
      name: name,
      logoUrl: optionalString(row['logo_url']),
      currencyCode: optionalString(row['currency_code']),
      timezone: optionalString(row['timezone']),
      settingsJson: parseSettingsJson(row['settings_json']),
      subscriptionTier: optionalString(row['subscription_tier']),
      subscriptionValidUntil: parseSubscriptionUntil(row['subscription_valid_until']),
    );
  }

  /// Trimmed name suitable for save payloads; null when empty or whitespace-only.
  static String? normalizeName(String input) => _trimmedOrNull(input);

  /// ISO 4217 code when non-empty; null when blank.
  static String? normalizeCurrencyCode(String? input) => _trimmedOrNull(input);

  /// IANA timezone id when non-empty; null when blank.
  static String? normalizeTimezone(String? input) => _trimmedOrNull(input);

  static String? _trimmedOrNull(String? input) {
    final trimmed = input?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  OrganizationProfile copyWith({
    String? id,
    String? name,
    String? logoUrl,
    String? currencyCode,
    String? timezone,
    Map<String, dynamic>? settingsJson,
    String? subscriptionTier,
    DateTime? subscriptionValidUntil,
  }) {
    return OrganizationProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      logoUrl: logoUrl ?? this.logoUrl,
      currencyCode: currencyCode ?? this.currencyCode,
      timezone: timezone ?? this.timezone,
      settingsJson: settingsJson ?? this.settingsJson,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      subscriptionValidUntil: subscriptionValidUntil ?? this.subscriptionValidUntil,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is OrganizationProfile &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            logoUrl == other.logoUrl &&
            currencyCode == other.currencyCode &&
            timezone == other.timezone &&
            mapEquals(settingsJson, other.settingsJson) &&
            subscriptionTier == other.subscriptionTier &&
            subscriptionValidUntil == other.subscriptionValidUntil;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    logoUrl,
    currencyCode,
    timezone,
    settingsJson == null
        ? null
        : Object.hashAllUnordered(
            settingsJson!.entries.map((e) => Object.hash(e.key, e.value)),
          ),
    subscriptionTier,
    subscriptionValidUntil,
  );
}
