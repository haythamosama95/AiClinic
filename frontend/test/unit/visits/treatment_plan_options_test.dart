import 'package:ai_clinic/features/visits/domain/treatment_plan_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('treatmentFrequencyOptions', () {
    test('trivial: exposes expected frequency wire values', () {
      final values = treatmentFrequencyOptions.map((o) => o.value).toList();
      expect(values, containsAll(['od', 'bd', 'tds', 'qid', 'q4h', 'q6h', 'q8h', 'prn', 'stat']));
      expect(values, hasLength(9));
    });

    test('advanced: each option has a non-empty label', () {
      for (final option in treatmentFrequencyOptions) {
        expect(option.label, isNotEmpty);
      }
    });
  });

  group('treatmentDurationOptions', () {
    test('trivial: exposes expected duration wire values', () {
      final values = treatmentDurationOptions.map((o) => o.value).toList();
      expect(values, containsAll(['3d', '5d', '7d', '10d', '14d', '21d', '30d', 'ongoing']));
      expect(values, hasLength(8));
    });
  });

  group('treatmentFrequencyLabel', () {
    test('trivial: maps known wire value to label', () {
      expect(treatmentFrequencyLabel('bd'), 'Twice daily');
      expect(treatmentFrequencyLabel('prn'), 'As needed');
    });

    test('edge case: returns em dash for null or blank input', () {
      expect(treatmentFrequencyLabel(null), '—');
      expect(treatmentFrequencyLabel(''), '—');
      expect(treatmentFrequencyLabel('   '), '—');
    });

    test('advanced: returns raw value for unknown codes', () {
      expect(treatmentFrequencyLabel('custom'), 'custom');
      expect(treatmentFrequencyLabel('BID'), 'BID');
    });
  });

  group('treatmentDurationLabel', () {
    test('trivial: maps known wire value to label', () {
      expect(treatmentDurationLabel('7d'), '7 days');
      expect(treatmentDurationLabel('ongoing'), 'Ongoing');
    });

    test('edge case: returns em dash for null or blank input', () {
      expect(treatmentDurationLabel(null), '—');
      expect(treatmentDurationLabel(''), '—');
    });

    test('advanced: returns raw value for unknown codes', () {
      expect(treatmentDurationLabel('14 days'), '14 days');
    });
  });
}
