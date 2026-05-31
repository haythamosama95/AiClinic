import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitListItem.fromRow', () {
    test('parses valid list_patient_visits row', () {
      final item = VisitListItem.fromRow({
        'id': 'visit-1',
        'visit_date': '2026-05-31',
        'doctor_name': 'Dr. Smith',
        'status': 'in_progress',
        'branch_name': 'Main Clinic',
      });

      expect(item, isNotNull);
      expect(item!.id, 'visit-1');
      expect(item.doctorName, 'Dr. Smith');
      expect(item.status, VisitStatus.inProgress);
      expect(item.branchName, 'Main Clinic');
      expect(item.visitDate.year, 2026);
      expect(item.visitDate.month, 5);
      expect(item.visitDate.day, 31);
    });

    test('returns null when required fields missing', () {
      expect(VisitListItem.fromRow({}), isNull);
      expect(VisitListItem.fromRow({'id': 'v1'}), isNull);
      expect(
        VisitListItem.fromRow({
          'id': 'v1',
          'visit_date': '2026-05-31',
          'doctor_name': '',
          'status': 'completed',
          'branch_name': 'Branch',
        }),
        isNull,
      );
    });

    test('returns null for invalid status', () {
      expect(
        VisitListItem.fromRow({
          'id': 'v1',
          'visit_date': '2026-05-31',
          'doctor_name': 'Dr. A',
          'status': 'unknown',
          'branch_name': 'Branch',
        }),
        isNull,
      );
    });

    test('stupid user: extra keys are ignored', () {
      final item = VisitListItem.fromRow({
        'id': 'v1',
        'visit_date': '2026-05-31',
        'doctor_name': 'Dr. A',
        'status': 'completed',
        'branch_name': 'Branch',
        'soap': {'subjective': 'hidden'},
      });
      expect(item, isNotNull);
    });
  });

  group('VisitListItem.copyWith', () {
    test('updates selected fields', () {
      final original = VisitListItem(
        id: 'v1',
        visitDate: DateTime.utc(2026, 5, 31),
        doctorName: 'Dr. A',
        status: VisitStatus.inProgress,
        branchName: 'Branch A',
      );
      final updated = original.copyWith(status: VisitStatus.completed, branchName: 'Branch B');
      expect(updated.status, VisitStatus.completed);
      expect(updated.branchName, 'Branch B');
      expect(updated.id, original.id);
    });
  });

  group('VisitListItem equality', () {
    test('equal items compare equal', () {
      final a = VisitListItem(
        id: 'v1',
        visitDate: DateTime.utc(2026, 5, 31),
        doctorName: 'Dr. A',
        status: VisitStatus.inProgress,
        branchName: 'Branch',
      );
      final b = VisitListItem(
        id: 'v1',
        visitDate: DateTime.utc(2026, 5, 31),
        doctorName: 'Dr. A',
        status: VisitStatus.inProgress,
        branchName: 'Branch',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
