import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitDetail.fromRow', () {
    test('parses full get_visit payload', () {
      final detail = VisitDetail.fromRow({
        'id': 'visit-1',
        'branch_id': 'branch-1',
        'appointment_id': 'appt-1',
        'patient_id': 'patient-1',
        'doctor_id': 'doctor-1',
        'doctor_name': 'Dr. Smith',
        'visit_date': '2026-05-31',
        'status': 'in_progress',
        'soap': {'subjective': 'Cough', 'updated_at': '2026-05-31T09:00:00Z'},
        'treatment_plans': [
          {'id': 'tp-1', 'visit_id': 'visit-1', 'patient_id': 'patient-1', 'medication_name': 'Drug'},
        ],
        'attachments': [
          {
            'id': 'att-1',
            'file_type': 'pdf',
            'uploaded_by': 'staff-1',
            'size_bytes': 500,
            'created_at': '2026-05-31T10:00:00Z',
          },
        ],
      });

      expect(detail, isNotNull);
      expect(detail!.status, VisitStatus.inProgress);
      expect(detail.soap?.subjective, 'Cough');
      expect(detail.treatmentPlans, hasLength(1));
      expect(detail.attachments, hasLength(1));
    });

    test('parses visit without nested collections', () {
      final detail = VisitDetail.fromRow({
        'id': 'visit-1',
        'branch_id': 'branch-1',
        'appointment_id': 'appt-1',
        'patient_id': 'patient-1',
        'doctor_id': 'doctor-1',
        'doctor_name': 'Dr. Smith',
        'visit_date': '2026-05-31',
        'status': 'completed',
      });

      expect(detail, isNotNull);
      expect(detail!.soap, isNull);
      expect(detail.treatmentPlans, isEmpty);
      expect(detail.attachments, isEmpty);
    });

    test('returns null when core fields missing', () {
      expect(VisitDetail.fromRow({}), isNull);
      expect(
        VisitDetail.fromRow({
          'id': 'visit-1',
          'branch_id': 'branch-1',
          'appointment_id': 'appt-1',
          'patient_id': 'patient-1',
          'doctor_id': 'doctor-1',
          'doctor_name': '',
          'visit_date': '2026-05-31',
          'status': 'in_progress',
        }),
        isNull,
      );
    });

    test('skips invalid nested items without failing', () {
      final detail = VisitDetail.fromRow({
        'id': 'visit-1',
        'branch_id': 'branch-1',
        'appointment_id': 'appt-1',
        'patient_id': 'patient-1',
        'doctor_id': 'doctor-1',
        'doctor_name': 'Dr. Smith',
        'visit_date': '2026-05-31',
        'status': 'in_progress',
        'treatment_plans': [
          {'id': 'bad'},
          'not-a-map',
        ],
        'attachments': [null, 42],
      });

      expect(detail!.treatmentPlans, isEmpty);
      expect(detail.attachments, isEmpty);
    });

    test('stupid user: soap without updated_at is ignored', () {
      final detail = VisitDetail.fromRow({
        'id': 'visit-1',
        'branch_id': 'branch-1',
        'appointment_id': 'appt-1',
        'patient_id': 'patient-1',
        'doctor_id': 'doctor-1',
        'doctor_name': 'Dr. Smith',
        'visit_date': '2026-05-31',
        'status': 'in_progress',
        'soap': {'subjective': 'orphan'},
      });
      expect(detail!.soap, isNull);
    });
  });

  group('VisitDetail.copyWith', () {
    test('updates status and nested soap', () {
      final original = VisitDetail(
        id: 'v1',
        branchId: 'b1',
        appointmentId: 'a1',
        patientId: 'p1',
        doctorId: 'd1',
        doctorName: 'Dr. A',
        visitDate: DateTime.utc(2026, 5, 31),
        status: VisitStatus.inProgress,
      );
      final updated = original.copyWith(status: VisitStatus.completed);
      expect(updated.status, VisitStatus.completed);
      expect(updated.id, original.id);
    });
  });
}
