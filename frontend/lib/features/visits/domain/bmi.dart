import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:flutter/foundation.dart';

/// Client-derived BMI from Height (cm) and Weight (kg) vital signs — never stored (FR-025).
@immutable
class BmiResult {
  const BmiResult({required this.value, required this.heightCm, required this.weightKg});

  final double value;
  final double heightCm;
  final double weightKg;

  /// BMI rounded to one decimal place for display.
  String get displayValue => value.toStringAsFixed(1);
}

/// Derives BMI when both Height and Weight vitals exist with parseable numeric values.
BmiResult? deriveBmiFromVitalSigns(List<VisitVitalSign> vitalSigns) {
  final heightSign = _findVitalByName(vitalSigns, 'Height');
  final weightSign = _findVitalByName(vitalSigns, 'Weight');
  if (heightSign == null || weightSign == null) {
    return null;
  }

  final heightCm = _parseVitalNumeric(heightSign.value);
  final weightKg = _parseVitalNumeric(weightSign.value);
  if (heightCm == null || weightKg == null || heightCm <= 0 || weightKg <= 0) {
    return null;
  }

  final heightM = heightCm / 100;
  final bmi = weightKg / (heightM * heightM);
  if (!bmi.isFinite || bmi <= 0) {
    return null;
  }

  return BmiResult(value: bmi, heightCm: heightCm, weightKg: weightKg);
}

VisitVitalSign? _findVitalByName(List<VisitVitalSign> vitalSigns, String name) {
  final target = name.trim().toLowerCase();
  for (final sign in vitalSigns) {
    if (sign.name.trim().toLowerCase() == target) {
      return sign;
    }
  }
  return null;
}

double? _parseVitalNumeric(String raw) {
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}
