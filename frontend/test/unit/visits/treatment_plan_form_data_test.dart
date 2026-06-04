import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const existing = TreatmentPlanItem(
    id: 'tp-1',
    visitId: 'v1',
    patientId: 'p1',
    medicationName: 'Ibuprofen',
    dosage: '500mg',
    frequency: 'BID',
    duration: '7 days',
    notes: 'Take with food',
  );

  group('TreatmentPlanFormData.updateParamsFor', () {
    test('omits unchanged optional fields on edit', () {
      final data = TreatmentPlanFormData(
        medicationName: 'Ibuprofen',
        dosage: '500mg',
        frequency: 'BID',
        duration: '10 days',
        notes: 'Take with food',
      );

      final params = data.updateParamsFor(existing);
      expect(params.medicationName, isNull);
      expect(params.dosage, isNull);
      expect(params.frequency, isNull);
      expect(params.duration, '10 days');
      expect(params.notes, isNull);
    });

    test('sends empty string when optional field is cleared', () {
      final data = TreatmentPlanFormData(
        medicationName: 'Ibuprofen',
        dosage: '',
        frequency: 'BID',
        duration: '7 days',
        notes: 'Take with food',
      );

      final params = data.updateParamsFor(existing);
      expect(params.dosage, '');
      expect(params.frequency, isNull);
    });

    test('includes medication name when changed', () {
      final data = TreatmentPlanFormData(
        medicationName: 'Ibuprofen XR',
        dosage: '500mg',
        frequency: 'BID',
        duration: '7 days',
        notes: 'Take with food',
      );

      expect(data.updateParamsFor(existing).medicationName, 'Ibuprofen XR');
    });

    test('does not expose legacy start or end dates', () {
      final withLegacy = existing.copyWith(
        startDate: DateTime.utc(2026, 5, 31),
        endDate: DateTime.utc(2026, 6, 6),
        duration: null,
      );
      final data = TreatmentPlanFormData(
        medicationName: 'Ibuprofen',
        dosage: '500mg',
        frequency: 'BID',
        duration: null,
        notes: 'Take with food',
      );

      final params = data.updateParamsFor(withLegacy);
      expect(params.medicationName, isNull);
      expect(params.dosage, isNull);
      expect(params.frequency, isNull);
      expect(params.duration, isNull);
      expect(params.notes, isNull);
    });
  });
}
