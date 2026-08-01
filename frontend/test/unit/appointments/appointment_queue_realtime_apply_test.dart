import 'package:ai_clinic/features/queue/data/queue_realtime_apply.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('applyAppointmentQueueRealtimeChange', () {
    final range = AppointmentTodayRange(from: DateTime.utc(2026, 6, 4, 0), to: DateTime.utc(2026, 6, 5, 0));

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
            'updated_at': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
          },
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items.single.startTime, DateTime.utc(2026, 6, 4, 11));
      expect(items.single.status, AppointmentStatus.confirmed);
      expect(items.single.updatedAt, DateTime.utc(2026, 6, 4, 10, 30));
    });

    test('update patches checked_in status with wait timestamps', () {
      final items = [item(status: AppointmentStatus.confirmed)];
      final checkedInAt = DateTime.utc(2026, 6, 4, 9, 45);

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': 'a1',
            'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
            'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
            'status': 'checked_in',
            'type': 'planned',
            'updated_at': checkedInAt.toIso8601String(),
            'checked_in_at': checkedInAt.toIso8601String(),
          },
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items.single.status, AppointmentStatus.checkedIn);
      expect(items.single.updatedAt, checkedInAt);
      expect(items.single.checkedInAt, checkedInAt);
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

    test('update keeps no-show appointment in queue with updated status', () {
      final items = [item(status: AppointmentStatus.confirmed)];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(
          eventType: PostgresChangeEvent.update,
          newRecord: {
            'id': 'a1',
            'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
            'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
            'status': 'no_show',
            'type': 'planned',
            'updated_at': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
          },
        ),
        todayRange: range,
      );

      expect(applied, isTrue);
      expect(items, hasLength(1));
      expect(items.single.status, AppointmentStatus.noShow);
    });

    test('delete removes row by id', () {
      final items = [item(), item(id: 'a2')];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.delete, oldRecord: {'id': 'a1'}),
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

    test('edge case: PostgresChangeEvent.all requires full refresh', () {
      final items = [item()];

      final applied = applyAppointmentQueueRealtimeChange(
        items: items,
        change: const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.all),
        todayRange: range,
      );

      expect(applied, isFalse);
      expect(items, hasLength(1));
    });

    group('delete', () {
      test('edge case: missing id returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: const AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.delete,
            oldRecord: {},
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
        expect(items, hasLength(1));
      });

      test('edge case: empty id returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: const AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.delete,
            oldRecord: {'id': ''},
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
      });

      test('edge case: absent id returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: const AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.delete,
            oldRecord: {'id': 'missing'},
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
        expect(items, hasLength(1));
      });
    });

    group('update guards', () {
      test('edge case: null record returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: const AppointmentQueueRealtimeChange(eventType: PostgresChangeEvent.update),
          todayRange: range,
        );

        expect(applied, isFalse);
      });

      test('edge case: missing id returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: const AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {'status': 'confirmed'},
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
      });

      test('edge case: unknown id returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'missing',
              'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
              'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
              'status': 'confirmed',
              'type': 'planned',
            },
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
      });

      test('edge case: null startTime returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'a1',
              'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
              'status': 'confirmed',
              'type': 'planned',
            },
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
        expect(items.single.status, AppointmentStatus.scheduled);
      });

      test('edge case: null endTime returns false', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'a1',
              'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
              'status': 'confirmed',
              'type': 'planned',
            },
          ),
          todayRange: range,
        );

        expect(applied, isFalse);
      });
    });

    group('update removals', () {
      test('update removes soft-deleted appointment from queue', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'a1',
              'is_deleted': true,
              'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
              'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
              'status': 'scheduled',
              'type': 'planned',
            },
          ),
          todayRange: range,
        );

        expect(applied, isTrue);
        expect(items, isEmpty);
      });

      test('update removes appointment moved outside today range', () {
        final items = [item()];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'a1',
              'start_time': DateTime.utc(2026, 6, 3, 10).toIso8601String(),
              'end_time': DateTime.utc(2026, 6, 3, 10, 30).toIso8601String(),
              'status': 'scheduled',
              'type': 'planned',
            },
          ),
          todayRange: range,
        );

        expect(applied, isTrue);
        expect(items, isEmpty);
      });
    });

    group('timestamp patching', () {
      test('update preserves timestamps when keys are absent', () {
        final existingUpdatedAt = DateTime.utc(2026, 6, 4, 8);
        final items = [
          item().copyWith(
            updatedAt: existingUpdatedAt,
            checkedInAt: DateTime.utc(2026, 6, 4, 8, 30),
            inProgressAt: DateTime.utc(2026, 6, 4, 9),
          ),
        ];

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
        expect(items.single.updatedAt, existingUpdatedAt);
        expect(items.single.checkedInAt, DateTime.utc(2026, 6, 4, 8, 30));
        expect(items.single.inProgressAt, DateTime.utc(2026, 6, 4, 9));
      });

      // Documents current behaviour, which is NOT the behaviour the production
      // code intends. `_applyUpdate` passes `containsKey(...) ? parsed : existing`
      // into `AppointmentListItem.copyWith`, but that `copyWith` coalesces with
      // `?? this.field`, so a null can never clear a timestamp and both ternary
      // branches collapse to the same result. Undoing a check-in over realtime
      // therefore leaves a stale `checkedInAt`. Flip these expectations to
      // `isNull` once `copyWith` adopts the sentinel pattern already used by
      // `AppointmentDetail.copyWith` (see core/utils/copy_with_sentinel.dart).
      test('regression: keys present with null cannot clear timestamps today', () {
        final items = [
          item().copyWith(
            updatedAt: DateTime.utc(2026, 6, 4, 8),
            checkedInAt: DateTime.utc(2026, 6, 4, 8, 30),
            inProgressAt: DateTime.utc(2026, 6, 4, 9),
          ),
        ];

        final applied = applyAppointmentQueueRealtimeChange(
          items: items,
          change: AppointmentQueueRealtimeChange(
            eventType: PostgresChangeEvent.update,
            newRecord: {
              'id': 'a1',
              'start_time': DateTime.utc(2026, 6, 4, 10).toIso8601String(),
              'end_time': DateTime.utc(2026, 6, 4, 10, 30).toIso8601String(),
              'status': 'scheduled',
              'type': 'planned',
              'updated_at': null,
              'checked_in_at': null,
              'in_progress_at': null,
            },
          ),
          todayRange: range,
        );

        expect(applied, isTrue);
        expect(items.single.updatedAt, DateTime.utc(2026, 6, 4, 8));
        expect(items.single.checkedInAt, DateTime.utc(2026, 6, 4, 8, 30));
        expect(items.single.inProgressAt, DateTime.utc(2026, 6, 4, 9));
      });
    });
  });
}
