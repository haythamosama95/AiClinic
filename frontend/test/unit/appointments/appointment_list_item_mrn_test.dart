import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal appointment list row for MRN parser tests (US6).
Map<String, dynamic> appointmentListRow({
  String? patientMrn,
  String? mrnAlias,
}) {
  return {
    'id': 'a1',
    'patient_id': 'p1',
    'patient_name': 'Ahmed Hassan',
    'doctor_id': 'd1',
    'doctor_name': 'Dr. Samir',
    'start_time': '2026-05-27T09:00:00.000Z',
    'end_time': '2026-05-27T09:20:00.000Z',
    'type': 'planned',
    'status': 'scheduled',
<<<<<<< HEAD
    if (patientMrn != null) 'patient_mrn': patientMrn,
    if (mrnAlias != null) 'mrn': mrnAlias,
=======
    'patient_mrn': ?patientMrn,
    'mrn': ?mrnAlias,
>>>>>>> master
  };
}

void main() {
  group('AppointmentListItem MRN parsing (US6)', () {
    test('fromRow parses patientMrn from list_appointments payload', () {
      final item = AppointmentListItem.fromRow(appointmentListRow(patientMrn: 'MRN-000042'));

      expect(item, isNotNull);
      expect(item!.patientMrn, 'MRN-000042');
    });

    test('fromRow falls back to mrn alias when patient_mrn absent', () {
      final item = AppointmentListItem.fromRow(appointmentListRow(mrnAlias: 'MRN-000099'));

      expect(item!.patientMrn, 'MRN-000099');
    });

    test('prefers patient_mrn over mrn when both present', () {
      final item = AppointmentListItem.fromRow(
        appointmentListRow(patientMrn: 'MRN-000001', mrnAlias: 'MRN-000002'),
      );

      expect(item!.patientMrn, 'MRN-000001');
    });

    test('fromRow leaves patientMrn null when patient_mrn absent', () {
      final item = AppointmentListItem.fromRow(appointmentListRow());

      expect(item!.patientMrn, isNull);
    });
  });
}
