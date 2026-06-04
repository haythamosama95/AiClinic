import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_today_range.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

/// Realtime postgres change forwarded from the queue subscription.
class AppointmentQueueRealtimeChange {
  const AppointmentQueueRealtimeChange({
    required this.eventType,
    this.oldRecord,
    this.newRecord,
  });

  final PostgresChangeEvent eventType;
  final Map<String, dynamic>? oldRecord;
  final Map<String, dynamic>? newRecord;
}

/// Applies a realtime change to the current queue when the payload is sufficient.
///
/// Returns `true` when [items] was updated in place; `false` when a full refresh is needed.
bool applyAppointmentQueueRealtimeChange({
  required List<AppointmentListItem> items,
  required AppointmentQueueRealtimeChange change,
  required AppointmentTodayRange todayRange,
}) {
  switch (change.eventType) {
    case PostgresChangeEvent.delete:
      return _removeByRecord(items, change.oldRecord);
    case PostgresChangeEvent.insert:
      return false;
    case PostgresChangeEvent.update:
      return _applyUpdate(items, change.newRecord, todayRange);
    case PostgresChangeEvent.all:
      return false;
  }
}

bool _removeByRecord(List<AppointmentListItem> items, Map<String, dynamic>? record) {
  final id = record?['id']?.toString();
  if (id == null || id.isEmpty) {
    return false;
  }
  final before = items.length;
  items.removeWhere((item) => item.id == id);
  return items.length != before;
}

bool _applyUpdate(
  List<AppointmentListItem> items,
  Map<String, dynamic>? record,
  AppointmentTodayRange todayRange,
) {
  if (record == null) {
    return false;
  }

  final id = record['id']?.toString();
  if (id == null || id.isEmpty) {
    return false;
  }

  final isDeleted = record['is_deleted'] == true;
  final status = AppointmentStatus.tryParse(record['status']?.toString());
  final startTime = parseAppointmentDateTime(record['start_time']);
  final endTime = parseAppointmentDateTime(record['end_time']);
  final type = AppointmentType.tryParse(record['type']?.toString());

  if (isDeleted || status == AppointmentStatus.cancelled || status == AppointmentStatus.noShow) {
    return _removeByRecord(items, record);
  }

  if (startTime != null && !appointmentStartTimeIsWithinRange(startTime, todayRange)) {
    return _removeByRecord(items, record);
  }

  final index = items.indexWhere((item) => item.id == id);
  if (index < 0) {
    return false;
  }

  final existing = items[index];
  if (startTime == null || endTime == null) {
    return false;
  }

  items[index] = existing.copyWith(
    startTime: startTime,
    endTime: endTime,
    status: status ?? existing.status,
    type: type ?? existing.type,
  );
  return true;
}
