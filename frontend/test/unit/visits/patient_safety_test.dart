import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AllergySeverityOptions', () {
    test('trivial: exposes known severity labels', () {
      expect(AllergySeverityOptions.items.keys, containsAll(['Mild', 'Moderate', 'Severe', 'Life-threatening']));
      expect(AllergySeverityOptions.items['Mild'], 'Mild');
    });
  });

  group('PatientAllergy.fromRow', () {
    test('trivial: parses allergy row', () {
      final allergy = PatientAllergy.fromRow({
        'id': 'a-1',
        'substance': 'Penicillin',
        'reaction': 'Rash',
      });
      expect(allergy, isNotNull);
      expect(allergy!.substance, 'Penicillin');
      expect(allergy.reaction, 'Rash');
    });

    test('edge case: returns null when id or substance missing or blank', () {
      expect(PatientAllergy.fromRow({}), isNull);
      expect(PatientAllergy.fromRow({'id': 'a-1', 'substance': '  '}), isNull);
    });

    test('edge case: treats blank reaction as null', () {
      expect(PatientAllergy.fromRow({'id': 'a-1', 'substance': 'Latex', 'reaction': '  '})!.reaction, isNull);
    });
  });

  group('PatientMedication.fromRow', () {
    test('trivial: parses medication row', () {
      final med = PatientMedication.fromRow({
        'id': 'm-1',
        'name': 'Metformin',
        'medication_id': 'cat-med-1',
        'note': 'With meals',
      });
      expect(med, isNotNull);
      expect(med!.name, 'Metformin');
      expect(med.medicationId, 'cat-med-1');
      expect(med.note, 'With meals');
    });

    test('edge case: returns null when id or name missing', () {
      expect(PatientMedication.fromRow({'name': 'Drug'}), isNull);
    });
  });

  group('PatientChronicCondition.fromRow', () {
    test('trivial: parses chronic condition row', () {
      final condition = PatientChronicCondition.fromRow({
        'id': 'c-1',
        'name': 'Hypertension',
        'note': 'Controlled',
      });
      expect(condition, isNotNull);
      expect(condition!.name, 'Hypertension');
      expect(condition.note, 'Controlled');
    });

    test('edge case: returns null when name blank', () {
      expect(PatientChronicCondition.fromRow({'id': 'c-1', 'name': ''}), isNull);
    });
  });

  group('PatientSafetyLastVital.fromRow', () {
    test('trivial: parses vital row', () {
      final vital = PatientSafetyLastVital.fromRow({
        'name': 'BP',
        'value': '120/80',
        'unit': 'mmHg',
      });
      expect(vital, isNotNull);
      expect(vital!.name, 'BP');
      expect(vital.value, '120/80');
      expect(vital.unit, 'mmHg');
    });

    test('edge case: returns null when name or value missing', () {
      expect(PatientSafetyLastVital.fromRow({'name': 'BP'}), isNull);
      expect(PatientSafetyLastVital.fromRow({'value': '98'}), isNull);
    });
  });

  group('PatientSafetyLastVitals.fromRow', () {
    test('trivial: parses vitals block with items', () {
      final vitals = PatientSafetyLastVitals.fromRow({
        'visit_id': 'visit-prior',
        'visit_date': '2026-05-01',
        'items': [
          {'name': 'HR', 'value': '72', 'unit': 'bpm'},
          {'name': 'BP', 'value': '120/80'},
        ],
      });

      expect(vitals.visitId, 'visit-prior');
      expect(vitals.visitDate, DateTime.utc(2026, 5, 1));
      expect(vitals.items, hasLength(2));
      expect(vitals.isEmpty, isFalse);
    });

    test('advanced: skips invalid items without failing', () {
      final vitals = PatientSafetyLastVitals.fromRow({
        'items': [
          {'name': 'HR', 'value': '72'},
          {'name': '', 'value': 'x'},
          'not-a-map',
        ],
      });
      expect(vitals.items, hasLength(1));
    });

    test('edge case: null row yields empty vitals', () {
      final vitals = PatientSafetyLastVitals.fromRow(null);
      expect(vitals.visitId, isNull);
      expect(vitals.items, isEmpty);
      expect(vitals.isEmpty, isTrue);
    });

    test('edge case: non-list items yields empty items', () {
      final vitals = PatientSafetyLastVitals.fromRow({'items': 'bad'});
      expect(vitals.items, isEmpty);
      expect(vitals.isEmpty, isTrue);
    });
  });

  group('PatientSafetyContext.fromRpcData', () {
    test('trivial: parses full safety context payload', () {
      final context = PatientSafetyContext.fromRpcData({
        'allergies': [
          {'id': 'a-1', 'substance': 'Penicillin'},
        ],
        'current_medications': [
          {'id': 'm-1', 'name': 'Aspirin'},
        ],
        'chronic_conditions': [
          {'id': 'c-1', 'name': 'Asthma'},
        ],
        'last_vitals': {
          'visit_id': 'v-prior',
          'visit_date': '2026-04-15',
          'items': [
            {'name': 'Temp', 'value': '37.0', 'unit': 'C'},
          ],
        },
      });

      expect(context.allergies, hasLength(1));
      expect(context.currentMedications, hasLength(1));
      expect(context.chronicConditions, hasLength(1));
      expect(context.lastVitals.items, hasLength(1));
      expect(context.hasStructuredData, isTrue);
    });

    test('advanced: null data yields empty context', () {
      final context = PatientSafetyContext.fromRpcData(null);
      expect(context.allergies, isEmpty);
      expect(context.hasStructuredData, isFalse);
    });

    test('edge case: skips invalid list entries', () {
      final context = PatientSafetyContext.fromRpcData({
        'allergies': [
          {'id': 'a-1', 'substance': 'Latex'},
          {'id': '', 'substance': 'Bad'},
          42,
        ],
        'current_medications': 'not-a-list',
      });
      expect(context.allergies, hasLength(1));
      expect(context.currentMedications, isEmpty);
    });

    test('edge case: hasStructuredData true when only last vitals present', () {
      final context = PatientSafetyContext.fromRpcData({
        'last_vitals': {
          'items': [
            {'name': 'SpO2', 'value': '98', 'unit': '%'},
          ],
        },
      });
      expect(context.hasStructuredData, isTrue);
    });

    test('invalid state: duplicate ids in list are preserved', () {
      final context = PatientSafetyContext.fromRpcData({
        'allergies': [
          {'id': 'dup', 'substance': 'A'},
          {'id': 'dup', 'substance': 'B'},
        ],
      });
      expect(context.allergies, hasLength(2));
    });
  });
}
