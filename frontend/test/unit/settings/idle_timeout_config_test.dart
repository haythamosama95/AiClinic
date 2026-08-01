import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdleTimeoutConfig', () {
    test('presetMinutes matches expected values', () {
      expect(IdleTimeoutConfig.presetMinutes, [5, 10, 15, 20, 30, 45, 60]);
    });

    group('tryParseMinutes', () {
      test('returns null for empty and whitespace input', () {
        expect(IdleTimeoutConfig.tryParseMinutes(''), isNull);
        expect(IdleTimeoutConfig.tryParseMinutes('   '), isNull);
      });

      test('returns null for non-numeric input', () {
        expect(IdleTimeoutConfig.tryParseMinutes('abc'), isNull);
        expect(IdleTimeoutConfig.tryParseMinutes('15m'), isNull);
      });

      test('returns null below min and above max', () {
        expect(IdleTimeoutConfig.tryParseMinutes('0'), isNull);
        expect(IdleTimeoutConfig.tryParseMinutes('121'), isNull);
        expect(IdleTimeoutConfig.tryParseMinutes('999999'), isNull);
      });

      test('accepts boundary values', () {
        expect(IdleTimeoutConfig.tryParseMinutes('1'), 1);
        expect(IdleTimeoutConfig.tryParseMinutes('120'), 120);
      });

      test('trims surrounding whitespace', () {
        expect(IdleTimeoutConfig.tryParseMinutes('  30  '), 30);
      });
    });

    group('clampMinutes', () {
      test('clamps below minimum', () {
        expect(IdleTimeoutConfig.clampMinutes(0), const Duration(minutes: 1));
        expect(IdleTimeoutConfig.clampMinutes(-5), const Duration(minutes: 1));
      });

      test('clamps above maximum', () {
        expect(IdleTimeoutConfig.clampMinutes(500), const Duration(minutes: 120));
      });

      test('passes through valid values', () {
        expect(IdleTimeoutConfig.clampMinutes(45), const Duration(minutes: 45));
      });
    });

    group('clampDuration', () {
      test('clamps duration using minute component', () {
        expect(IdleTimeoutConfig.clampDuration(const Duration(minutes: 200)), const Duration(minutes: 120));
        expect(IdleTimeoutConfig.clampDuration(const Duration(minutes: 10)), const Duration(minutes: 10));
      });
    });

    group('formatDuration', () {
      test('uses singular minute label for one minute', () {
        expect(IdleTimeoutConfig.formatDuration(const Duration(minutes: 1)), '1 minute');
      });

      test('uses plural minutes label for other values', () {
        expect(IdleTimeoutConfig.formatDuration(const Duration(minutes: 2)), '2 minutes');
        expect(IdleTimeoutConfig.formatDuration(const Duration(minutes: 60)), '60 minutes');
      });
    });
  });
}
