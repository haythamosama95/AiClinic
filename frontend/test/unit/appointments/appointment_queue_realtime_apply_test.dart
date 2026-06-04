import 'package:ai_clinic/features/appointments/data/appointment_queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('applyAppointmentQueueRealtimeChange', () {
    final range = AppointmentTodayRange(
      from: DateTime.utc(2026, 6, 4, 0),
      to: DateTime.utc(2026, 6, 5, 0),
    );

    AppointmentListItem item({
      String id = 'a1',
      DateTime? startTime,
      AppointmentStatus status = AppointmentStatus.scheduled,
    }) {
      final start = startTime ?? DateTime.utc(2026, 6, 4, 10);
      return AppointmentListItem(
        id: id,
        patientId: 'p1',
        patientName: 'Pat',
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        type: AppointmentType.planned,
        status: status,
      );
    }

    test('update patches existing row in place', () {
      final items = [item()];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': 'a1',
            'start_time': DateTime.utc(2026, 6, 4, 11).toIso8601String(),
            'end_time': DateTime.utc(2026, 6, 4, 11, 30).toIso8601String(),
            'status': 'confirmed',
            'type': 'planned',
          },
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items.single.startTime, DateTime.utc(2026, 6, 4, 11));
      expect(items.single.status, AppointmentStatus.confirmed);
    });

    test('update removes cancelled appointment from queue', () {
      final items = [item()];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': 'a1',
            'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
            'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
            'status': 'cancelled',
            'type': 'planned',
          },
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items, isEmpty);
    });

    test('delete removes row by id', () {
      final items = [item(), item(id: 'a2')];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.delete,
          oldRecord: {'id': 'a1'},
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items, hasLength(1));
      expect(items.single.id, 'a2');
    });

    test('insert requires full refresh', () {
      final items = [item()];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.insert, newRecord: {'id': 'new'}),
        todayRange: range,
      );

      expect(applied, isFalse);
      expect(items, hasLength(1));
    });
  });
}
