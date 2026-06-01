import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreatmentPlanItem.fromRow', () {
    test('parses full treatment plan row', () {
      final item = TreatmentPlanItem.fromRow({
        'id': 'tp-1',
        'visit_id': 'visit-1',
        'patient_id': 'patient-1',
        'medication_name': 'Ibuprofen',
        'dosage': '400mg',
        'frequency': 'BID',
        'duration': '7 days',
        'notes': 'Take with food',
      });

      expect(item, isNotNull);
      expect(item!.medicationName, 'Ibuprofen');
      expect(item.dosage, '400mg');
      expect(item.duration, '7 days');
    });

    test('parses minimal required fields', () {
      final item = TreatmentPlanItem.fromRow({
        'id': 'tp-1',
        'visit_id': 'visit-1',
        'patient_id': 'patient-1',
        'medication_name': 'Aspirin',
      });
      expect(item, isNotNull);
      expect(item!.dosage, isNull);
      expect(item.startDate, isNull);
    });

    test('parses get_visit payload using parent visit and patient ids', () {
      final item = TreatmentPlanItem.fromRow(
        {'id': 'tp-1', 'medication_name': 'Aspirin', 'duration': '5 days'},
        visitId: 'visit-1',
        patientId: 'patient-1',
      );

      expect(item, isNotNull);
      expect(item!.visitId, 'visit-1');
      expect(item.patientId, 'patient-1');
      expect(item.duration, '5 days');
    });

    test('returns null when medication_name empty', () {
      expect(
        TreatmentPlanItem.fromRow({
          'id': 'tp-1',
          'visit_id': 'visit-1',
          'patient_id': 'patient-1',
          'medication_name': '   ',
        }),
        isNull,
      );
    });

    test('returns null when ids missing', () {
      expect(TreatmentPlanItem.fromRow({'medication_name': 'Drug'}), isNull);
    });
  });

  group('TreatmentPlanItem.copyWith', () {
    test('updates medication and optional fields', () {
      const original = TreatmentPlanItem(id: 'tp-1', visitId: 'v1', patientId: 'p1', medicationName: 'Drug A');
      final updated = original.copyWith(medicationName: 'Drug B', dosage: '10mg');
      expect(updated.medicationName, 'Drug B');
      expect(updated.dosage, '10mg');
    });
  });
}
