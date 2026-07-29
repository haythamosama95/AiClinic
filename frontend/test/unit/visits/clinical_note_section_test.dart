import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClinicalNoteSection.abbr', () {
    test('trivial: maps each section to its single-letter abbreviation', () {
      expect(ClinicalNoteSection.complaint.abbr, 'C');
      expect(ClinicalNoteSection.history.abbr, 'H');
      expect(ClinicalNoteSection.examination.abbr, 'E');
      expect(ClinicalNoteSection.diagnosis.abbr, 'D');
      expect(ClinicalNoteSection.plan.abbr, 'P');
    });

    test('advanced: covers every enum value exhaustively', () {
      final expected = {
        ClinicalNoteSection.complaint: 'C',
        ClinicalNoteSection.history: 'H',
        ClinicalNoteSection.examination: 'E',
        ClinicalNoteSection.diagnosis: 'D',
        ClinicalNoteSection.plan: 'P',
      };
      for (final section in ClinicalNoteSection.values) {
        expect(section.abbr, expected[section], reason: '$section abbr');
      }
      expect(ClinicalNoteSection.values, hasLength(expected.length));
    });
  });

  group('ClinicalNoteSection.label', () {
    test('trivial: maps each section to its display label', () {
      expect(ClinicalNoteSection.complaint.label, 'Complaint');
      expect(ClinicalNoteSection.history.label, 'History');
      expect(ClinicalNoteSection.examination.label, 'Examination');
      expect(ClinicalNoteSection.diagnosis.label, 'Diagnosis');
      expect(ClinicalNoteSection.plan.label, 'Plan');
    });

    test('advanced: covers every enum value exhaustively', () {
      final expected = {
        ClinicalNoteSection.complaint: 'Complaint',
        ClinicalNoteSection.history: 'History',
        ClinicalNoteSection.examination: 'Examination',
        ClinicalNoteSection.diagnosis: 'Diagnosis',
        ClinicalNoteSection.plan: 'Plan',
      };
      for (final section in ClinicalNoteSection.values) {
        expect(section.label, expected[section], reason: '$section label');
      }
    });
  });
}
