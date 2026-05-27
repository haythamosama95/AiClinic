import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _listRow({String? status, String? type}) => {
  'id': 'a1',
  'patient_id': 'p1',
  'patient_name': '  Ahmed Hassan  ',
  'doctor_id': 'd1',
  'doctor_name': 'Dr. Samir',
  'start_time': '2026-05-27T09:00:00.000Z',
  'end_time': '2026-05-27T09:20:00.000Z',
  'type': type ?? 'planned',
  'status': status ?? 'scheduled',
};

void main() {
  group('AppointmentListItem.fromRow', () {
    test('parses complete list_appointments row', () {
      final item = AppointmentListItem.fromRow(_listRow());

      expect(item, isNotNull);
      expect(item!.patientName, 'Ahmed Hassan');
      expect(item.type, AppointmentType.planned);
      expect(item.status, AppointmentStatus.scheduled);
      expect(item.startTime, DateTime.parse('2026-05-27T09:00:00.000Z'));
      expect(item.endTime, DateTime.parse('2026-05-27T09:20:00.000Z'));
    });

    test('parses walk-in checked_in row', () {
      final item = AppointmentListItem.fromRow(_listRow(type: 'walk_in', status: 'checked_in'));

      expect(item!.type, AppointmentType.walkIn);
      expect(item.status, AppointmentStatus.checkedIn);
    });

    test('returns null when required fields missing or blank', () {
      expect(AppointmentListItem.fromRow({..._listRow(), 'id': ''}), isNull);
      expect(AppointmentListItem.fromRow({..._listRow(), 'patient_name': '  '}), isNull);
      expect(AppointmentListItem.fromRow({..._listRow(), 'doctor_id': ''}), isNull);
      expect(AppointmentListItem.fromRow({..._listRow(), 'start_time': null}), isNull);
      expect(AppointmentListItem.fromRow({..._listRow(), 'end_time': 'not-a-date'}), isNull);
    });

    test('returns null for invalid type or status', () {
      expect(AppointmentListItem.fromRow({..._listRow(), 'type': 'emergency'}), isNull);
      expect(AppointmentListItem.fromRow({..._listRow(), 'status': 'waiting'}), isNull);
    });

    test('edge case: end before start still parses (validation is server-side)', () {
      final item = AppointmentListItem.fromRow({
        ..._listRow(),
        'start_time': '2026-05-27T10:00:00.000Z',
        'end_time': '2026-05-27T09:00:00.000Z',
      });

      expect(item, isNotNull);
      expect(item!.endTime.isBefore(item.startTime), isTrue);
    });

    test('stupid user: unexpected types coerced via toString', () {
      final item = AppointmentListItem.fromRow({
        'id': 12345,
        'patient_id': true,
        'patient_name': 999,
        'doctor_id': 1,
        'doctor_name': 'Doc',
        'start_time': DateTime.utc(2026, 5, 27, 9),
        'end_time': DateTime.utc(2026, 5, 27, 9, 20),
        'type': 'planned',
        'status': 'scheduled',
      });

      expect(item!.id, '12345');
      expect(item.patientId, 'true');
      expect(item.patientName, '999');
    });
  });

  group('AppointmentListItem equality', () {
    test('copyWith preserves unchanged fields', () {
      final original = AppointmentListItem.fromRow(_listRow())!;
      final updated = original.copyWith(patientName: 'New Name');

      expect(updated.patientName, 'New Name');
      expect(updated.id, original.id);
      expect(original == updated, isFalse);
    });

    test('regression: identical rows are equal', () {
      final a = AppointmentListItem.fromRow(_listRow());
      final b = AppointmentListItem.fromRow(_listRow());

      expect(a, equals(b));
    });
  });
}
