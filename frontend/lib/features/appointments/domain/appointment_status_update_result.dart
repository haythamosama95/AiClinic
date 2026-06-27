import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:flutter/foundation.dart';

/// Successful result from `update_appointment_status`, including server timestamps.
@immutable
class AppointmentStatusUpdateResult {
  const AppointmentStatusUpdateResult({required this.status, this.updatedAt, this.checkedInAt, this.inProgressAt});

  final AppointmentStatus status;
  final DateTime? updatedAt;
  final DateTime? checkedInAt;
  final DateTime? inProgressAt;

  static AppointmentStatusUpdateResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final status = AppointmentStatus.tryParse(data['status']?.toString());
    if (status == null) {
      return null;
    }

    return AppointmentStatusUpdateResult(
      status: status,
      updatedAt: parseAppointmentDateTime(data['updated_at']),
      checkedInAt: parseAppointmentDateTime(data['checked_in_at']),
      inProgressAt: parseAppointmentDateTime(data['in_progress_at']),
    );
  }
}
