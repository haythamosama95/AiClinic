import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CreateAppointmentResult', () {
    Map<String, dynamic> validPayload({
      String? appointmentId,
      String? startTime,
      String? endTime,
      String? status,
      String? type,
    }) {
      return {
        'appointment_id': appointmentId ?? 'appt-123',
        'start_time': startTime ?? '2026-06-04T09:00:00.000Z',
        'end_time': endTime ?? '2026-06-04T09:30:00.000Z',
        'status': status ?? 'scheduled',
        'type': type ?? 'planned',
      };
    }

    test('invalid state: fromRpcData returns null for null payload', () {
      expect(CreateAppointmentResult.fromRpcData(null), isNull);
    });

    test('invalid state: fromRpcData returns null when required fields are missing', () {
      final base = validPayload();
      final requiredFields = ['appointment_id', 'start_time', 'end_time', 'status', 'type'];

      for (final field in requiredFields) {
        final payload = Map<String, dynamic>.from(base)..remove(field);
        expect(CreateAppointmentResult.fromRpcData(payload), isNull, reason: 'missing $field');
      }
    });

    test('invalid state: fromRpcData returns null for empty appointment id', () {
      expect(CreateAppointmentResult.fromRpcData(validPayload(appointmentId: '   ')), isNull);
    });

    test('advanced: fromRpcData maps a fully valid payload', () {
      final result = CreateAppointmentResult.fromRpcData(validPayload());

      expect(result, isNotNull);
      expect(result!.appointmentId, 'appt-123');
      expect(result.startTime, DateTime.utc(2026, 6, 4, 9));
      expect(result.endTime, DateTime.utc(2026, 6, 4, 9, 30));
      expect(result.status, AppointmentStatus.scheduled);
      expect(result.type, AppointmentType.planned);
    });

    test('invalid state: malformed timestamps return null', () {
      expect(CreateAppointmentResult.fromRpcData(validPayload(startTime: 'bad')), isNull);
      expect(CreateAppointmentResult.fromRpcData(validPayload(endTime: 'also-bad')), isNull);
    });

    test('invalid state: unknown status or type strings return null', () {
      expect(CreateAppointmentResult.fromRpcData(validPayload(status: 'mystery')), isNull);
      expect(CreateAppointmentResult.fromRpcData(validPayload(type: 'walk_in')), isNull);
    });
  });
}
