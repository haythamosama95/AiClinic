import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_location_input.dart';

void main() {
  group('googleMapsUriFor', () {
    test('returns search entry point when value is empty', () {
      expect(googleMapsUriFor(''), Uri.parse('https://www.google.com/maps/search/?api=1'));
    });

    test('returns absolute http(s) URLs unchanged', () {
      const url = 'https://maps.google.com/?q=clinic';
      expect(googleMapsUriFor(url), Uri.parse(url));
    });

    test('normalizes bare domains to https', () {
      expect(googleMapsUriFor('maps.google.com/place/test'), Uri.parse('https://maps.google.com/place/test'));
    });

    test('encodes free-text addresses as map search queries', () {
      expect(
        googleMapsUriFor('123 Nile Street, Cairo'),
        Uri.parse('https://www.google.com/maps/search/?api=1&query=123%20Nile%20Street%2C%20Cairo'),
      );
    });
  });
}
