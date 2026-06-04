import 'package:ai_clinic/features/visits/domain/soap_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SoapNote.fromRow', () {
    test('parses full SOAP row with specialty JSON', () {
      final note = SoapNote.fromRow({
        'subjective': 'Headache',
        'objective': 'BP normal',
        'assessment': 'Tension',
        'plan': 'Rest',
        'specialty_form_json': {'pain_scale': 3},
        'updated_at': '2026-05-31T10:00:00Z',
      });

      expect(note, isNotNull);
      expect(note!.subjective, 'Headache');
      expect(note.specialtyFormJson['pain_scale'], 3);
      expect(note.updatedAt.toUtc(), DateTime.utc(2026, 5, 31, 10));
    });

    test('returns null when updated_at missing', () {
      expect(SoapNote.fromRow({'subjective': 'x'}), isNull);
    });

    test('defaults specialty_form_json to empty map', () {
      final note = SoapNote.fromRow({'updated_at': '2026-05-31T10:00:00Z'});
      expect(note!.specialtyFormJson, isEmpty);
    });

    test('stupid user: invalid specialty JSON becomes empty map', () {
      final note = SoapNote.fromRow({'updated_at': '2026-05-31T10:00:00Z', 'specialty_form_json': 'not-a-map'});
      expect(note!.specialtyFormJson, isEmpty);
    });
  });

  group('SoapNote.hasAnySection', () {
    test('false when all sections empty or whitespace', () {
      final note = SoapNote(updatedAt: DateTime.utc(2026, 5, 31));
      expect(note.hasAnySection, isFalse);

      final whitespace = SoapNote(subjective: '   ', updatedAt: DateTime.utc(2026, 5, 31));
      expect(whitespace.hasAnySection, isFalse);
    });

    test('true when any section has content', () {
      final note = SoapNote(plan: 'Follow up', updatedAt: DateTime.utc(2026, 5, 31));
      expect(note.hasAnySection, isTrue);
    });
  });

  group('SoapNote.copyWith', () {
    test('clears section with explicit null', () {
      final note = SoapNote(subjective: 'Pain', updatedAt: DateTime.utc(2026, 5, 31));
      final cleared = note.copyWith(subjective: null);
      expect(cleared.subjective, isNull);
    });
  });

  group('soapSectionLengthError', () {
    test('returns null when all sections are within limit', () {
      expect(soapSectionLengthError(subjective: 'ok', objective: '', assessment: '', plan: ''), isNull);
    });

    test('returns null when a section is exactly at the limit', () {
      final atLimit = 'x' * kMaxSoapSectionLength;
      expect(soapSectionLengthError(subjective: atLimit, objective: '', assessment: '', plan: ''), isNull);
    });

    test('returns error when any section exceeds the limit', () {
      final overLimit = 'x' * (kMaxSoapSectionLength + 1);
      expect(
        soapSectionLengthError(subjective: '', objective: overLimit, assessment: '', plan: ''),
        'Each SOAP section must be 10,000 characters or fewer.',
      );
    });
  });
}
