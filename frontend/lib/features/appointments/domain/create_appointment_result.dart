import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter/foundation.dart';

/// Result payload from `create_appointment` RPC (V1-4).
@immutable
class CreateAppointmentResult {
  const CreateAppointmentResult({
    required this.appointmentId,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.type,
  });

  final String appointmentId;
  final DateTime startTime;
  final DateTime endTime;
  final AppointmentStatus status;
  final AppointmentType type;

  static CreateAppointmentResult? fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }

    final id = data['appointment_id']?.toString();
    final startTime = parseAppointmentDateTime(data['start_time']);
    final endTime = parseAppointmentDateTime(data['end_time']);
    final status = AppointmentStatus.tryParse(data['status']?.toString());
    final type = AppointmentType.tryParse(data['type']?.toString());

    if (id == null || id.isEmpty || startTime == null || endTime == null || status == null || type == null) {
      return null;
    }

    return CreateAppointmentResult(
      appointmentId: id,
      startTime: startTime,
      endTime: endTime,
      status: status,
      type: type,
    );
  }
}
