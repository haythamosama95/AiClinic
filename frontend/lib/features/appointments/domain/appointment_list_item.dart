import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter/foundation.dart';

/// Appointment row for calendar, queue, and schedule lists (V1-4).
@immutable
class AppointmentListItem {
  const AppointmentListItem({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.status,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final DateTime startTime;
  final DateTime endTime;
  final AppointmentType type;
  final AppointmentStatus status;

  static AppointmentListItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final patientId = row['patient_id']?.toString();
    final patientName = row['patient_name']?.toString().trim();
    final doctorId = row['doctor_id']?.toString();
    final doctorName = row['doctor_name']?.toString().trim();
    final startTime = parseAppointmentDateTime(row['start_time']);
    final endTime = parseAppointmentDateTime(row['end_time']);
    final type = AppointmentType.tryParse(row['type']?.toString());
    final status = AppointmentStatus.tryParse(row['status']?.toString());

    if (id == null ||
        id.isEmpty ||
        patientId == null ||
        patientId.isEmpty ||
        patientName == null ||
        patientName.isEmpty ||
        doctorId == null ||
        doctorId.isEmpty ||
        doctorName == null ||
        doctorName.isEmpty ||
        startTime == null ||
        endTime == null ||
        type == null ||
        status == null) {
      return null;
    }

    return AppointmentListItem(
      id: id,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
      doctorName: doctorName,
      startTime: startTime,
      endTime: endTime,
      type: type,
      status: status,
    );
  }

  AppointmentListItem copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? doctorId,
    String? doctorName,
    DateTime? startTime,
    DateTime? endTime,
    AppointmentType? type,
    AppointmentStatus? status,
  }) {
    return AppointmentListItem(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      type: type ?? this.type,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentListItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            patientId == other.patientId &&
            patientName == other.patientName &&
            doctorId == other.doctorId &&
            doctorName == other.doctorName &&
            startTime == other.startTime &&
            endTime == other.endTime &&
            type == other.type &&
            status == other.status;
  }

  @override
  int get hashCode => Object.hash(id, patientId, patientName, doctorId, doctorName, startTime, endTime, type, status);
}
