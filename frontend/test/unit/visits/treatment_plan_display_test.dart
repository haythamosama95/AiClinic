import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreatmentPlanDisplay.subtitleParts', () {
    test('includes dosage, frequency, and duration text', () {
      const plan = TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'v1',
        patientId: 'p1',
        medicationName: 'Amoxicillin',
        dosage: '500mg',
        frequency: 'BID',
        duration: '7 days',
      );

      expect(TreatmentPlanDisplay.subtitleParts(plan), ['500mg', 'BID', '7 days']);
    });

    test('omits empty optional fields', () {
      const plan = TreatmentPlanItem(id: 'tp-1', visitId: 'v1', patientId: 'p1', medicationName: 'Aspirin');

      expect(TreatmentPlanDisplay.subtitleParts(plan), isEmpty);
    });

    test('legacy start/end dates format as duration span', () {
      final plan = TreatmentPlanItem(
        id: 'tp-1',
        visitId: 'v1',
        patientId: 'p1',
        medicationName: 'Ibuprofen',
        startDate: DateTime.utc(2026, 5, 31),
        endDate: DateTime.utc(2026, 6, 6),
      );

      expect(TreatmentPlanDisplay.subtitleParts(plan), contains('May 31, 2026 – Jun 6, 2026'));
    });
  });
}
