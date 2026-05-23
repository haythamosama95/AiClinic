import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientSearchQuery', () {
    test('trivial: empty query is browse mode', () {
      expect(PatientSearchQuery.validationHint(''), isNull);
      expect(PatientSearchQuery.validationHint('   '), isNull);
      expect(PatientSearchQuery.canInvokeRpc(''), isTrue);
    });

    test('name search requires 3 characters', () {
      expect(PatientSearchQuery.validationHint('ab'), isNotNull);
      expect(PatientSearchQuery.validationHint('ahm'), isNull);
      expect(PatientSearchQuery.isPhonePrefixQuery('ahm'), isFalse);
    });

    test('phone prefix requires 2 digits', () {
      expect(PatientSearchQuery.isPhonePrefixQuery('2010'), isTrue);
      expect(PatientSearchQuery.validationHint('2'), isNotNull);
      expect(PatientSearchQuery.validationHint('20'), isNull);
    });

    test('stupid usage: spaces trimmed before digit detection', () {
      expect(PatientSearchQuery.isPhonePrefixQuery('  20 '), isTrue);
      expect(PatientSearchQuery.validationHint('  20 '), isNull);
    });

    test('edge case: unicode name uses name rules', () {
      expect(PatientSearchQuery.validationHint('أح'), isNotNull);
      expect(PatientSearchQuery.validationHint('أحمد'), isNull);
    });
  });
}
