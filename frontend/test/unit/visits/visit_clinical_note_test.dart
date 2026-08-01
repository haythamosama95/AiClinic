import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // clinicalSectionLengthError per-field over-limit cases: encounter_section_length_test.dart

  group('kMaxClinicalSectionLength', () {
    test('trivial: matches backend validation limit', () {
      expect(kMaxClinicalSectionLength, 10000);
    });
  });

  group('VisitClinicalNote.fromRow', () {
    test('trivial: parses full documentation row', () {
      final note = VisitClinicalNote.fromRow({
        'complaint': 'Headache',
        'history': 'Two days',
        'examination': 'Normal',
        'diagnosis': 'Tension',
        'plan': 'Rest',
        'updated_at': '2026-05-31T09:00:00Z',
      });

      expect(note, isNotNull);
      expect(note!.complaint, 'Headache');
      expect(note.history, 'Two days');
      expect(note.examination, 'Normal');
      expect(note.diagnosis, 'Tension');
      expect(note.plan, 'Rest');
      expect(note.updatedAt, DateTime.utc(2026, 5, 31, 9));
    });

    test('advanced: returns note with all-null sections for empty row', () {
      final note = VisitClinicalNote.fromRow({});
      expect(note, isNotNull);
      expect(note!.complaint, isNull);
      expect(note.updatedAt, isNull);
    });

    test('edge case: trims sections and treats whitespace-only as null', () {
      final note = VisitClinicalNote.fromRow({
        'complaint': '  Cough  ',
        'history': '   ',
        'plan': '',
      });
      expect(note!.complaint, 'Cough');
      expect(note.history, isNull);
      expect(note.plan, isNull);
    });

    test('invalid state: ignores unexpected extra keys', () {
      final note = VisitClinicalNote.fromRow({'complaint': 'Pain', 'extra': 'ignored'});
      expect(note!.complaint, 'Pain');
    });
  });

  group('VisitClinicalNote.hasContent', () {
    test('trivial: true when any section has non-whitespace text', () {
      expect(const VisitClinicalNote(complaint: 'Pain').hasContent, isTrue);
      expect(const VisitClinicalNote(plan: 'Follow up').hasContent, isTrue);
    });

    test('edge case: false when all sections null, empty, or whitespace-only', () {
      expect(const VisitClinicalNote().hasContent, isFalse);
      expect(const VisitClinicalNote(complaint: '', history: '  ').hasContent, isFalse);
    });

    test('advanced: true for trimmed content in any section', () {
      expect(const VisitClinicalNote(examination: '  WNL  ').hasContent, isTrue);
    });
  });

  group('VisitClinicalNote equality', () {
    test('trivial: equal when all fields match', () {
      final updatedAt = DateTime.utc(2026, 5, 31);
      final a = VisitClinicalNote(complaint: 'C', updatedAt: updatedAt);
      final b = VisitClinicalNote(complaint: 'C', updatedAt: updatedAt);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('edge case: differs when updatedAt differs', () {
      final a = VisitClinicalNote(updatedAt: DateTime.utc(2026, 5, 31));
      final b = VisitClinicalNote(updatedAt: DateTime.utc(2026, 6, 1));
      expect(a, isNot(equals(b)));
    });
  });
}
