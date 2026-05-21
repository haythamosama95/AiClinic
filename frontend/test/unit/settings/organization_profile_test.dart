import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrganizationProfile.fromRow', () {
    test('parses full organization row', () {
      final profile = OrganizationProfile.fromRow({
        'id': 'org-1',
        'name': '  Downtown Clinic  ',
        'logo_url': 'https://cdn.example/logo.png',
        'currency_code': 'EGP',
        'timezone': 'Africa/Cairo',
        'settings_json': {'receipt_footer': 'Thank you'},
        'subscription_tier': 'standard',
        'subscription_valid_until': '2026-12-31T00:00:00.000Z',
      });

      expect(profile, isNotNull);
      expect(profile!.id, 'org-1');
      expect(profile.name, 'Downtown Clinic');
      expect(profile.logoUrl, 'https://cdn.example/logo.png');
      expect(profile.currencyCode, 'EGP');
      expect(profile.timezone, 'Africa/Cairo');
      expect(profile.settingsJson, {'receipt_footer': 'Thank you'});
      expect(profile.subscriptionTier, 'standard');
      expect(profile.subscriptionValidUntil, isNotNull);
    });

    test('returns null when id or name missing', () {
      expect(OrganizationProfile.fromRow({'id': '', 'name': 'X'}), isNull);
      expect(OrganizationProfile.fromRow({'id': 'x', 'name': ''}), isNull);
      expect(OrganizationProfile.fromRow({'id': 'x'}), isNull);
      expect(OrganizationProfile.fromRow({}), isNull);
    });

    test('treats blank optional strings as null', () {
      final profile = OrganizationProfile.fromRow({
        'id': 'org-1',
        'name': 'Clinic',
        'logo_url': '   ',
        'currency_code': '',
        'timezone': null,
      });

      expect(profile!.logoUrl, isNull);
      expect(profile.currencyCode, isNull);
      expect(profile.timezone, isNull);
    });

    test('parses settings_json from generic Map', () {
      final profile = OrganizationProfile.fromRow({
        'id': 'org-1',
        'name': 'Clinic',
        'settings_json': {1: 'numeric-key'},
      });

      expect(profile!.settingsJson, {'1': 'numeric-key'});
    });

    test('ignores invalid settings_json shapes', () {
      final profile = OrganizationProfile.fromRow({'id': 'org-1', 'name': 'Clinic', 'settings_json': 'not-json'});

      expect(profile!.settingsJson, isNull);
    });

    test('ignores unparseable subscription_valid_until', () {
      final profile = OrganizationProfile.fromRow({
        'id': 'org-1',
        'name': 'Clinic',
        'subscription_valid_until': 'not-a-date',
      });

      expect(profile!.subscriptionValidUntil, isNull);
    });
  });

  group('OrganizationProfile normalization', () {
    test('normalizeName rejects whitespace-only input', () {
      expect(OrganizationProfile.normalizeName(''), isNull);
      expect(OrganizationProfile.normalizeName('   \t\n  '), isNull);
    });

    test('normalizeName trims valid input', () {
      expect(OrganizationProfile.normalizeName('  Main Clinic  '), 'Main Clinic');
    });

    test('normalizeCurrencyCode and normalizeTimezone trim or null', () {
      expect(OrganizationProfile.normalizeCurrencyCode('  egp '), 'egp');
      expect(OrganizationProfile.normalizeCurrencyCode(''), isNull);
      expect(OrganizationProfile.normalizeTimezone(' Africa/Cairo '), 'Africa/Cairo');
    });
  });

  group('OrganizationProfile.copyWith and equality', () {
    test('copyWith overrides only provided fields', () {
      const original = OrganizationProfile(id: 'org-1', name: 'A', currencyCode: 'USD');
      final updated = original.copyWith(name: 'B');

      expect(updated.id, 'org-1');
      expect(updated.name, 'B');
      expect(updated.currencyCode, 'USD');
    });

    test('equality compares settingsJson deeply', () {
      const a = OrganizationProfile(id: '1', name: 'X', settingsJson: {'a': 1});
      const b = OrganizationProfile(id: '1', name: 'X', settingsJson: {'a': 1});
      const c = OrganizationProfile(id: '1', name: 'X', settingsJson: {'a': 2});

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
