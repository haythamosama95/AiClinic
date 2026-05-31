import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitStatus.tryParse', () {
    test('parses all lifecycle wire values', () {
      expect(VisitStatus.tryParse('in_progress'), VisitStatus.inProgress);
      expect(VisitStatus.tryParse('completed'), VisitStatus.completed);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(VisitStatus.tryParse('  IN_PROGRESS '), VisitStatus.inProgress);
      expect(VisitStatus.tryParse('\tCOMPLETED\n'), VisitStatus.completed);
    });

    test('returns null for empty or unrecognized values', () {
      expect(VisitStatus.tryParse(null), isNull);
      expect(VisitStatus.tryParse(''), isNull);
      expect(VisitStatus.tryParse('pending'), isNull);
      expect(VisitStatus.tryParse('in-progress'), isNull);
      expect(VisitStatus.tryParse('checked_in'), isNull);
    });

    test('malformed user input does not throw', () {
      expect(() => VisitStatus.tryParse('null'), returnsNormally);
      expect(VisitStatus.tryParse('null'), isNull);
    });
  });

  group('VisitStatus.wireValue', () {
    test('round-trips with tryParse', () {
      for (final status in VisitStatus.values) {
        expect(VisitStatus.tryParse(status.wireValue), status);
      }
    });
  });

  group('VisitStatus.isTerminal', () {
    test('completed is terminal', () {
      expect(VisitStatus.completed.isTerminal, isTrue);
    });

    test('in_progress is not terminal', () {
      expect(VisitStatus.inProgress.isTerminal, isFalse);
    });
  });

  group('VisitStatus.canTransitionTo', () {
    test('in_progress may transition to completed only', () {
      expect(VisitStatus.inProgress.canTransitionTo(VisitStatus.completed), isTrue);
      expect(VisitStatus.inProgress.canTransitionTo(VisitStatus.inProgress), isFalse);
    });

    test('completed cannot transition', () {
      expect(VisitStatus.completed.canTransitionTo(VisitStatus.inProgress), isFalse);
      expect(VisitStatus.completed.canTransitionTo(VisitStatus.completed), isFalse);
    });
  });

  group('VisitStatus.label', () {
    test('provides human-readable labels', () {
      expect(VisitStatus.inProgress.label, 'In progress');
      expect(VisitStatus.completed.label, 'Completed');
    });
  });
}
