import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientSearchQuery.helperForDraft', () {
    test('empty query shows browse guidance', () {
      final helper = PatientSearchQuery.helperForDraft('');
      expect(helper, contains('Browse'));
      expect(helper, contains('3+'));
      expect(helper, contains('2+'));
    });

    test('whitespace-only query shows browse guidance', () {
      expect(PatientSearchQuery.helperForDraft('   '), contains('Browse'));
    });

    test('phone-like input shows phone helper', () {
      expect(PatientSearchQuery.helperForDraft('20'), contains('Phone prefix'));
      expect(PatientSearchQuery.helperForDraft('2010'), contains('Phone prefix'));
    });

    test('name-like input shows name helper', () {
      expect(PatientSearchQuery.helperForDraft('ahm'), contains('Name search'));
      expect(PatientSearchQuery.helperForDraft('ahmed'), contains('Name search'));
    });

    test('single digit shows phone helper', () {
      expect(PatientSearchQuery.helperForDraft('2'), contains('Phone prefix'));
    });

    test('two letter name shows name helper', () {
      expect(PatientSearchQuery.helperForDraft('ab'), contains('Name search'));
    });
  });

  group('PatientSearchQuery.canInvokeRpc', () {
    test('null query can invoke', () {
      expect(PatientSearchQuery.canInvokeRpc(null), isTrue);
    });

    test('empty string can invoke (browse mode)', () {
      expect(PatientSearchQuery.canInvokeRpc(''), isTrue);
    });

    test('valid name (3+ chars) can invoke', () {
      expect(PatientSearchQuery.canInvokeRpc('ahm'), isTrue);
      expect(PatientSearchQuery.canInvokeRpc('ahmed hassan'), isTrue);
    });

    test('too short name cannot invoke', () {
      expect(PatientSearchQuery.canInvokeRpc('ab'), isFalse);
      expect(PatientSearchQuery.canInvokeRpc('a'), isFalse);
    });

    test('valid phone prefix (2+ digits) can invoke', () {
      expect(PatientSearchQuery.canInvokeRpc('20'), isTrue);
      expect(PatientSearchQuery.canInvokeRpc('201055'), isTrue);
    });

    test('single digit cannot invoke', () {
      expect(PatientSearchQuery.canInvokeRpc('2'), isFalse);
    });

    test('whitespace-padded valid query can invoke', () {
      expect(PatientSearchQuery.canInvokeRpc('  ahmed  '), isTrue);
      expect(PatientSearchQuery.canInvokeRpc('  20  '), isTrue);
    });
  });

  group('PatientSearchQuery.isPhonePrefixQuery edge cases', () {
    test('all digits returns true', () {
      expect(PatientSearchQuery.isPhonePrefixQuery('0'), isTrue);
      expect(PatientSearchQuery.isPhonePrefixQuery('1234567890'), isTrue);
    });

    test('mixed letters and digits returns false', () {
      expect(PatientSearchQuery.isPhonePrefixQuery('20abc'), isFalse);
      expect(PatientSearchQuery.isPhonePrefixQuery('+20'), isFalse);
    });

    test('special characters return false', () {
      expect(PatientSearchQuery.isPhonePrefixQuery('+'), isFalse);
      expect(PatientSearchQuery.isPhonePrefixQuery('-'), isFalse);
      expect(PatientSearchQuery.isPhonePrefixQuery('(20)'), isFalse);
    });

    test('empty string does not match (checked after trim)', () {
      expect(PatientSearchQuery.isPhonePrefixQuery(''), isFalse);
    });
  });

  group('PatientSearchQuery.validationHint boundary cases', () {
    test('exactly 2 chars name: still below threshold', () {
      expect(PatientSearchQuery.validationHint('ab'), isNotNull);
    });

    test('exactly 3 chars name: passes threshold', () {
      expect(PatientSearchQuery.validationHint('abc'), isNull);
    });

    test('exactly 1 digit: below threshold', () {
      expect(PatientSearchQuery.validationHint('5'), isNotNull);
    });

    test('exactly 2 digits: passes threshold', () {
      expect(PatientSearchQuery.validationHint('55'), isNull);
    });

    test('very long query is valid', () {
      expect(PatientSearchQuery.validationHint('a' * 500), isNull);
    });

    test('very long digits query is valid', () {
      expect(PatientSearchQuery.validationHint('1' * 100), isNull);
    });

    test('null input returns null (browse mode)', () {
      expect(PatientSearchQuery.validationHint(null), isNull);
    });

    test('name hint contains "3 characters"', () {
      final hint = PatientSearchQuery.validationHint('ab');
      expect(hint, contains('3'));
      expect(hint, contains('character'));
    });

    test('phone hint contains "2 digits"', () {
      final hint = PatientSearchQuery.validationHint('5');
      expect(hint, contains('2'));
      expect(hint, contains('digit'));
    });
  });
}
