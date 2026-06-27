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
  });
}
