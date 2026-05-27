import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_row_parsing.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter/foundation.dart';

/// Full appointment profile for detail and mutation flows (V1-4).
@immutable
class AppointmentDetail {
  const AppointmentDetail({
    required this.id,
    required this.branchId,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.queueNumber,
    this.notes,
    this.cancelReason,
    this.createdByDisplay,
  });

  final String id;
  final String branchId;
  final String patientId;
  final String patientName;
  final String doctorId;
  final String doctorName;
  final DateTime startTime;
  final DateTime endTime;
  final AppointmentType type;
  final AppointmentStatus status;
  final int? queueNumber;
  final String? notes;
  final String? cancelReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdByDisplay;

  static AppointmentDetail? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final branchId = row['branch_id']?.toString();
    final patientId = row['patient_id']?.toString();
    final patientName = row['patient_name']?.toString().trim();
    final doctorId = row['doctor_id']?.toString();
    final doctorName = row['doctor_name']?.toString().trim();
    final startTime = parseAppointmentDateTime(row['start_time']);
    final endTime = parseAppointmentDateTime(row['end_time']);
    final type = AppointmentType.tryParse(row['type']?.toString());
    final status = AppointmentStatus.tryParse(row['status']?.toString());
    final createdAt = parseAppointmentDateTime(row['created_at']);
    final updatedAt = parseAppointmentDateTime(row['updated_at']);

    if (id == null ||
        id.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
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
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return AppointmentDetail(
      id: id,
      branchId: branchId,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
      doctorName: doctorName,
      startTime: startTime,
      endTime: endTime,
      type: type,
      status: status,
      queueNumber: optionalAppointmentInt(row['queue_number']),
      notes: optionalAppointmentString(row['notes']),
      cancelReason: optionalAppointmentString(row['cancel_reason']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdByDisplay: optionalAppointmentString(row['created_by_display'] ?? row['created_by_name']),
    );
  }

  AppointmentDetail copyWith({
    String? id,
    String? branchId,
    String? patientId,
    String? patientName,
    String? doctorId,
    String? doctorName,
    DateTime? startTime,
    DateTime? endTime,
    AppointmentType? type,
    AppointmentStatus? status,
    Object? queueNumber = copyWithSentinel,
    Object? notes = copyWithSentinel,
    Object? cancelReason = copyWithSentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? createdByDisplay = copyWithSentinel,
  }) {
    return AppointmentDetail(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      type: type ?? this.type,
      status: status ?? this.status,
      queueNumber: identical(queueNumber, copyWithSentinel) ? this.queueNumber : queueNumber as int?,
      notes: identical(notes, copyWithSentinel) ? this.notes : notes as String?,
      cancelReason: identical(cancelReason, copyWithSentinel) ? this.cancelReason : cancelReason as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdByDisplay: identical(createdByDisplay, copyWithSentinel)
          ? this.createdByDisplay
          : createdByDisplay as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentDetail &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            branchId == other.branchId &&
            patientId == other.patientId &&
            patientName == other.patientName &&
            doctorId == other.doctorId &&
            doctorName == other.doctorName &&
            startTime == other.startTime &&
            endTime == other.endTime &&
            type == other.type &&
            status == other.status &&
            queueNumber == other.queueNumber &&
            notes == other.notes &&
            cancelReason == other.cancelReason &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            createdByDisplay == other.createdByDisplay;
  }

  @override
  int get hashCode => Object.hash(
    id,
    branchId,
    patientId,
    patientName,
    doctorId,
    doctorName,
    startTime,
    endTime,
    type,
    status,
    queueNumber,
    notes,
    cancelReason,
    createdAt,
    updatedAt,
    createdByDisplay,
  );
}
