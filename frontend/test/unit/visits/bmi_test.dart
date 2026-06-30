import 'package:ai_clinic/features/visits/domain/bmi.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveBmiFromVitalSigns', () {
    test('derives BMI from Height (cm) and Weight (kg)', () {
      final result = deriveBmiFromVitalSigns(const [
        VisitVitalSign(id: 'h1', name: 'Height', value: '180', unit: 'cm'),
        VisitVitalSign(id: 'w1', name: 'Weight', value: '81', unit: 'kg'),
      ]);

      expect(result, isNotNull);
      expect(result!.heightCm, 180);
      expect(result.weightKg, 81);
      expect(result.value, closeTo(25.0, 0.05));
      expect(result.displayValue, '25.0');
    });

    test('matches vital names case-insensitively', () {
      final result = deriveBmiFromVitalSigns(const [
        VisitVitalSign(id: 'h1', name: ' height ', value: '170'),
        VisitVitalSign(id: 'w1', name: 'WEIGHT', value: '68'),
      ]);

      expect(result, isNotNull);
      expect(result!.value, closeTo(23.5, 0.1));
    });

    test('returns null when Height is missing', () {
      expect(deriveBmiFromVitalSigns(const [VisitVitalSign(id: 'w1', name: 'Weight', value: '70')]), isNull);
    });

    test('returns null when Weight is missing', () {
      expect(deriveBmiFromVitalSigns(const [VisitVitalSign(id: 'h1', name: 'Height', value: '170')]), isNull);
    });

    test('returns null for non-numeric values', () {
      expect(
        deriveBmiFromVitalSigns(const [
          VisitVitalSign(id: 'h1', name: 'Height', value: 'tall'),
          VisitVitalSign(id: 'w1', name: 'Weight', value: '70'),
        ]),
        isNull,
      );
    });

    test('returns null for zero or negative measurements', () {
      expect(
        deriveBmiFromVitalSigns(const [
          VisitVitalSign(id: 'h1', name: 'Height', value: '0'),
          VisitVitalSign(id: 'w1', name: 'Weight', value: '70'),
        ]),
        isNull,
      );
    });

    test('parses comma-separated numbers', () {
      final result = deriveBmiFromVitalSigns(const [
        VisitVitalSign(id: 'h1', name: 'Height', value: '175.5'),
        VisitVitalSign(id: 'w1', name: 'Weight', value: '70,2'),
      ]);

      expect(result, isNotNull);
      expect(result!.value, greaterThan(0));
    });
  });
}
