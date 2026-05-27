import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _detailRow({Map<String, dynamic>? overrides}) => {
  'id': 'a1',
  'branch_id': 'b1',
  'patient_id': 'p1',
  'patient_name': 'Sara Ali',
  'doctor_id': 'd1',
  'doctor_name': 'Dr. Samir',
  'start_time': '2026-05-27T09:00:00.000Z',
  'end_time': '2026-05-27T09:20:00.000Z',
  'type': 'planned',
  'status': 'scheduled',
  'queue_number': null,
  'notes': 'First visit',
  'cancel_reason': null,
  'created_at': '2026-05-26T08:00:00.000Z',
  'updated_at': '2026-05-26T08:00:00.000Z',
  'created_by_display': 'Reception',
  ...?overrides,
};

void main() {
  group('AppointmentDetail.fromRow', () {
    test('parses full appointment detail payload', () {
      final detail = AppointmentDetail.fromRow(_detailRow());

      expect(detail, isNotNull);
      expect(detail!.branchId, 'b1');
      expect(detail.type, AppointmentType.planned);
      expect(detail.status, AppointmentStatus.scheduled);
      expect(detail.notes, 'First visit');
      expect(detail.createdByDisplay, 'Reception');
      expect(detail.queueNumber, isNull);
    });

    test('parses appointment without assigned doctor', () {
      final detail = AppointmentDetail.fromRow(_detailRow(overrides: {'doctor_id': null, 'doctor_name': null}));

      expect(detail, isNotNull);
      expect(detail!.doctorId, isNull);
      expect(detail.doctorDisplayName, 'Unassigned');
    });

    test('accepts created_by_name alias for audit display', () {
      final detail = AppointmentDetail.fromRow(
        _detailRow(overrides: {'created_by_display': null, 'created_by_name': 'Admin User'}),
      );

      expect(detail!.createdByDisplay, 'Admin User');
    });

    test('returns null without required audit timestamps', () {
      expect(AppointmentDetail.fromRow(_detailRow(overrides: {'created_at': null})), isNull);
      expect(AppointmentDetail.fromRow(_detailRow(overrides: {'updated_at': 'bad-date'})), isNull);
    });

    test('returns null for invalid type or status even with valid timestamps', () {
      expect(AppointmentDetail.fromRow(_detailRow(overrides: {'type': 'invalid'})), isNull);
      expect(AppointmentDetail.fromRow(_detailRow(overrides: {'status': 'pending'})), isNull);
    });

    test('strips blank optional profile fields', () {
      final detail = AppointmentDetail.fromRow(_detailRow(overrides: {'notes': '   ', 'cancel_reason': '\t'}));

      expect(detail!.notes, isNull);
      expect(detail.cancelReason, isNull);
    });

    test('parses cancelled appointment with cancel reason', () {
      final detail = AppointmentDetail.fromRow(
        _detailRow(overrides: {'status': 'cancelled', 'cancel_reason': 'Patient requested'}),
      );

      expect(detail!.status, AppointmentStatus.cancelled);
      expect(detail.cancelReason, 'Patient requested');
    });

    test('edge case: queue_number unused in V1-4 but parseable when present', () {
      final detail = AppointmentDetail.fromRow(_detailRow(overrides: {'queue_number': 42}));

      expect(detail!.queueNumber, 42);
    });

    test('stupid user: non-numeric queue_number yields null', () {
      final detail = AppointmentDetail.fromRow(_detailRow(overrides: {'queue_number': 'not-a-number'}));

      expect(detail!.queueNumber, isNull);
    });
  });

  group('AppointmentDetail.copyWith', () {
    test('updates status while preserving identity fields', () {
      final original = AppointmentDetail.fromRow(_detailRow())!;
      final updated = original.copyWith(status: AppointmentStatus.checkedIn);

      expect(updated.status, AppointmentStatus.checkedIn);
      expect(updated.id, original.id);
      expect(updated.patientId, original.patientId);
    });

    test('clears optional notes via copyWith sentinel pattern', () {
      final original = AppointmentDetail.fromRow(_detailRow())!;
      final cleared = original.copyWith(notes: null);

      expect(cleared.notes, isNull);
    });
  });
}
