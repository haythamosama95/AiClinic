import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_update_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentStatusUpdateResult', () {
    test('BUG-001: parses server timestamps from RPC data', () {
      final result = AppointmentStatusUpdateResult.fromRpcData({
        'status': 'checked_in',
        'updated_at': '2026-06-04T10:00:00.000Z',
        'checked_in_at': '2026-06-04T09:45:00.000Z',
        'in_progress_at': null,
      });

      expect(result, isNotNull);
      expect(result!.status, AppointmentStatus.checkedIn);
      expect(result.checkedInAt, DateTime.utc(2026, 6, 4, 9, 45));
      expect(result.updatedAt, DateTime.utc(2026, 6, 4, 10));
      expect(result.inProgressAt, isNull);
    });

    test('invalid state: fromRpcData returns null for null payload', () {
      expect(AppointmentStatusUpdateResult.fromRpcData(null), isNull);
    });

    test('invalid state: fromRpcData returns null when status is missing', () {
      expect(AppointmentStatusUpdateResult.fromRpcData({'updated_at': '2026-06-04T10:00:00.000Z'}), isNull);
    });

    test('invalid state: fromRpcData returns null for unparseable status', () {
      expect(
        AppointmentStatusUpdateResult.fromRpcData({'status': 'not_a_real_status'}),
        isNull,
      );
    });

    test('advanced: fromRpcData maps all optional timestamps when present', () {
      final result = AppointmentStatusUpdateResult.fromRpcData({
        'status': 'in_progress',
        'updated_at': '2026-06-04T11:00:00.000Z',
        'checked_in_at': '2026-06-04T09:45:00.000Z',
        'in_progress_at': '2026-06-04T10:30:00.000Z',
      });

      expect(result, isNotNull);
      expect(result!.status, AppointmentStatus.inProgress);
      expect(result.updatedAt, DateTime.utc(2026, 6, 4, 11));
      expect(result.checkedInAt, DateTime.utc(2026, 6, 4, 9, 45));
      expect(result.inProgressAt, DateTime.utc(2026, 6, 4, 10, 30));
    });

    test('edge case: fromRpcData accepts absent optional timestamps', () {
      final result = AppointmentStatusUpdateResult.fromRpcData({'status': 'scheduled'});

      expect(result, isNotNull);
      expect(result!.status, AppointmentStatus.scheduled);
      expect(result.updatedAt, isNull);
      expect(result.checkedInAt, isNull);
      expect(result.inProgressAt, isNull);
    });

    test('invalid state: malformed timestamp strings become null fields', () {
      final result = AppointmentStatusUpdateResult.fromRpcData({
        'status': 'confirmed',
        'updated_at': 'not-a-timestamp',
        'checked_in_at': '',
        'in_progress_at': 'also-bad',
      });

      expect(result, isNotNull);
      expect(result!.status, AppointmentStatus.confirmed);
      expect(result.updatedAt, isNull);
      expect(result.checkedInAt, isNull);
      expect(result.inProgressAt, isNull);
    });
  });
}
