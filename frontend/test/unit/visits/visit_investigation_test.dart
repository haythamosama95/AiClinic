import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitInvestigation.fromRow', () {
    test('trivial: parses full investigation row', () {
      final investigation = VisitInvestigation.fromRow({
        'id': 'inv-1',
        'name': 'CBC',
        'note': 'Fasting',
        'investigation_id': 'cat-cbc',
        'result': 'Normal',
        'result_recorded_at': '2026-05-31T14:00:00Z',
        'ordered_visit_id': 'visit-prior',
        'ordered_visit_date': '2026-05-01',
      });

      expect(investigation, isNotNull);
      expect(investigation!.id, 'inv-1');
      expect(investigation.name, 'CBC');
      expect(investigation.note, 'Fasting');
      expect(investigation.investigationId, 'cat-cbc');
      expect(investigation.result, 'Normal');
      expect(investigation.resultRecordedAt, DateTime.utc(2026, 5, 31, 14));
      expect(investigation.orderedVisitId, 'visit-prior');
      expect(investigation.orderedVisitDate, DateTime.utc(2026, 5, 1));
    });

    test('advanced: parses minimal required fields', () {
      final investigation = VisitInvestigation.fromRow({'id': 'inv-2', 'name': 'X-Ray'});
      expect(investigation, isNotNull);
      expect(investigation!.note, isNull);
      expect(investigation.result, isNull);
      expect(investigation.orderedVisitId, isNull);
    });

    test('edge case: returns null when id or name missing or blank', () {
      expect(VisitInvestigation.fromRow({}), isNull);
      expect(VisitInvestigation.fromRow({'id': '', 'name': 'CBC'}), isNull);
      expect(VisitInvestigation.fromRow({'id': 'inv-1', 'name': '   '}), isNull);
    });

    test('edge case: trims name and treats blank optional strings as null', () {
      final investigation = VisitInvestigation.fromRow({
        'id': 'inv-3',
        'name': '  MRI  ',
        'note': '  ',
        'result': '',
      });
      expect(investigation!.name, 'MRI');
      expect(investigation.note, isNull);
      expect(investigation.result, isNull);
    });

    test('invalid state: coerces numeric id to string', () {
      final investigation = VisitInvestigation.fromRow({'id': 99, 'name': 'CBC'});
      expect(investigation!.id, '99');
    });
  });

  group('VisitInvestigation.hasResult', () {
    test('trivial: true when result has non-whitespace text', () {
      const investigation = VisitInvestigation(id: 'i1', name: 'CBC', result: 'Normal');
      expect(investigation.hasResult, isTrue);
    });

    test('edge case: false when result is null, empty, or whitespace-only', () {
      expect(const VisitInvestigation(id: 'i1', name: 'CBC').hasResult, isFalse);
      expect(const VisitInvestigation(id: 'i1', name: 'CBC', result: '').hasResult, isFalse);
      expect(const VisitInvestigation(id: 'i1', name: 'CBC', result: '   ').hasResult, isFalse);
    });
  });

  group('VisitInvestigation.isPendingFromPriorVisit', () {
    test('trivial: true when ordered_visit_id is present', () {
      const investigation = VisitInvestigation(id: 'i1', name: 'CBC', orderedVisitId: 'prior-visit');
      expect(investigation.isPendingFromPriorVisit, isTrue);
    });

    test('edge case: false when ordered_visit_id is absent', () {
      expect(const VisitInvestigation(id: 'i1', name: 'CBC').isPendingFromPriorVisit, isFalse);
    });
  });

  group('VisitInvestigation equality', () {
    test('trivial: equal when id, name, note, and investigationId match', () {
      const a = VisitInvestigation(id: 'i1', name: 'CBC', note: 'Fasting', investigationId: 'cat-1');
      const b = VisitInvestigation(id: 'i1', name: 'CBC', note: 'Fasting', investigationId: 'cat-1');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('edge case: differs when name changes', () {
      const a = VisitInvestigation(id: 'i1', name: 'CBC');
      const b = VisitInvestigation(id: 'i1', name: 'X-Ray');
      expect(a, isNot(equals(b)));
    });

    test('regression: result and ordered fields are excluded from equality', () {
      const withResult = VisitInvestigation(
        id: 'i1',
        name: 'CBC',
        result: 'Normal',
        orderedVisitId: 'prior',
      );
      const withoutResult = VisitInvestigation(id: 'i1', name: 'CBC');
      expect(withResult, equals(withoutResult));
    });
  });
}
