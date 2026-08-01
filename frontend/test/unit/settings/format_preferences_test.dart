import 'package:ai_clinic/features/settings/domain/format_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDateFormat', () {
    test('defaultValue is dmy', () {
      expect(AppDateFormat.defaultValue, AppDateFormat.dmy);
    });

    test('tryParse returns null for null input', () {
      expect(AppDateFormat.tryParse(null), isNull);
    });

    test('tryParse returns matching enum for valid storage values', () {
      expect(AppDateFormat.tryParse('dmy'), AppDateFormat.dmy);
      expect(AppDateFormat.tryParse('mdy'), AppDateFormat.mdy);
    });

    test('tryParse returns null for unknown values', () {
      expect(AppDateFormat.tryParse(''), isNull);
      expect(AppDateFormat.tryParse('ymd'), isNull);
      expect(AppDateFormat.tryParse('DMY'), isNull);
    });

    test('each value exposes storageValue and label', () {
      expect(AppDateFormat.dmy.storageValue, 'dmy');
      expect(AppDateFormat.dmy.label, 'DD/MM/YYYY');
      expect(AppDateFormat.mdy.storageValue, 'mdy');
      expect(AppDateFormat.mdy.label, 'MM/DD/YYYY');
    });
  });

  group('AppTimeFormat', () {
    test('defaultValue is h12', () {
      expect(AppTimeFormat.defaultValue, AppTimeFormat.h12);
    });

    test('tryParse returns null for null input', () {
      expect(AppTimeFormat.tryParse(null), isNull);
    });

    test('tryParse returns matching enum for valid storage values', () {
      expect(AppTimeFormat.tryParse('12h'), AppTimeFormat.h12);
      expect(AppTimeFormat.tryParse('24h'), AppTimeFormat.h24);
    });

    test('tryParse returns null for unknown values', () {
      expect(AppTimeFormat.tryParse(''), isNull);
      expect(AppTimeFormat.tryParse('12H'), isNull);
      expect(AppTimeFormat.tryParse('military'), isNull);
    });

    test('each value exposes storageValue and label', () {
      expect(AppTimeFormat.h12.storageValue, '12h');
      expect(AppTimeFormat.h12.label, '12-hour (3:30 PM)');
      expect(AppTimeFormat.h24.storageValue, '24h');
      expect(AppTimeFormat.h24.label, '24-hour (15:30)');
    });
  });
}
