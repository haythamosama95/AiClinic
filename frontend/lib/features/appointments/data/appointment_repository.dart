import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/supabase_config.dart' show supabaseClientProvider;
import 'package:ai_clinic/core/rpc/app_rpc_invoker.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';

/// Appointment scheduling RPC wrappers (V1-4).
class AppointmentRepository with AppRpcInvoker {
  AppointmentRepository(this._client);

  final SupabaseClient _client;

  @override
  SupabaseClient get rpcClient => _client;

  @override
  String get migrationHint => '20260526140000_appointment_management.sql';

  @override
  String get rpcLogDomain => 'appointments';

  Future<AppointmentSettings> getSettings({required String branchId}) async {
    final id = branchId.trim();
    if (id.isEmpty) {
      throw RpcFailure(
        const RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Branch id is required.'),
      );
    }

    final result = await invokeRpc('get_appointment_settings', {'p_branch_id': id});
    final settings = AppointmentSettings.fromRpcData(result.data);
    if (settings == null) {
      throw StateError('Appointment settings were returned in an unexpected shape.');
    }
    return settings;
  }

  Future<int> setDefaultDuration({required int durationMinutes, String? branchId}) async {
    _assertDurationMinutes(durationMinutes);

    final params = <String, dynamic>{
      'p_duration_minutes': durationMinutes,
      if (branchId != null && branchId.trim().isNotEmpty) 'p_branch_id': branchId.trim(),
    };

    final result = await invokeRpc('set_appointment_default_duration', params);
    final parsed = AppointmentSettings.fromRpcData(
      result.data != null ? {'default_duration_minutes': result.data!['default_duration_minutes']} : null,
    );
    return parsed?.defaultDurationMinutes ?? durationMinutes;
  }

  Future<CreateAppointmentResult> createAppointment({
    required String branchId,
    required String patientId,
    required String doctorId,
    required AppointmentType type,
    DateTime? startTime,
    int? durationMinutes,
    DateTime? endTime,
    String? notes,
  }) async {
    _assertNonEmpty('branchId', branchId);
    _assertNonEmpty('patientId', patientId);
    _assertNonEmpty('doctorId', doctorId);

    if (durationMinutes != null) {
      _assertDurationMinutes(durationMinutes);
    }

    if (notes != null && notes.trim().length > 2000) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Notes must be 2000 characters or fewer.',
        ),
      );
    }

    if (type == AppointmentType.planned && startTime == null) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Start time is required for planned appointments.',
        ),
      );
    }

    final params = <String, dynamic>{
      'p_branch_id': branchId.trim(),
      'p_patient_id': patientId.trim(),
      'p_doctor_id': doctorId.trim(),
      'p_type': type.wireValue,
      if (startTime != null) 'p_start_time': startTime.toUtc().toIso8601String(),
      if (durationMinutes != null) 'p_duration_minutes': durationMinutes,
      if (endTime != null) 'p_end_time': endTime.toUtc().toIso8601String(),
      if (notes != null && notes.trim().isNotEmpty) 'p_notes': notes.trim(),
    };

    final result = await invokeRpc('create_appointment', params);
    final created = CreateAppointmentResult.fromRpcData(result.data);
    if (created == null) {
      throw StateError('Create appointment returned an unexpected shape.');
    }
    return created;
  }

  Future<List<AppointmentListItem>> listAppointments({
    required String branchId,
    required DateTime from,
    required DateTime to,
    String? doctorId,
    List<AppointmentStatus>? statuses,
  }) async {
    _assertNonEmpty('branchId', branchId);

    if (!to.isAfter(from)) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'End of range must be after the start.',
        ),
      );
    }

    final params = <String, dynamic>{
      'p_branch_id': branchId.trim(),
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
      if (doctorId != null && doctorId.trim().isNotEmpty) 'p_doctor_id': doctorId.trim(),
      if (statuses != null && statuses.isNotEmpty)
        'p_statuses': statuses.map((s) => s.wireValue).toList(growable: false),
    };

    final result = await invokeRpc('list_appointments', params);
    final rawItems = result.data?['items'];
    if (rawItems is! List) {
      return const [];
    }

    return [
      for (final item in rawItems)
        if (item is Map<String, dynamic>)
          AppointmentListItem.fromRow(item)
        else if (item is Map)
          AppointmentListItem.fromRow(Map<String, dynamic>.from(item)),
    ].whereType<AppointmentListItem>().toList(growable: false);
  }

  Future<AppointmentStatus> updateStatus({required String appointmentId, required AppointmentStatus newStatus}) async {
    _assertNonEmpty('appointmentId', appointmentId);

    final result = await invokeRpc('update_appointment_status', {
      'p_appointment_id': appointmentId.trim(),
      'p_new_status': newStatus.wireValue,
    });

    final status = AppointmentStatus.tryParse(result.data?['status']?.toString());
    if (status == null) {
      throw StateError('Update status returned an unexpected shape.');
    }
    return status;
  }

  Future<CreateAppointmentResult> reschedule({
    required String appointmentId,
    required DateTime startTime,
    int? durationMinutes,
    DateTime? endTime,
  }) async {
    _assertNonEmpty('appointmentId', appointmentId);

    if (durationMinutes != null) {
      _assertDurationMinutes(durationMinutes);
    }

    final result = await invokeRpc('reschedule_appointment', {
      'p_appointment_id': appointmentId.trim(),
      'p_start_time': startTime.toUtc().toIso8601String(),
      'p_duration_minutes': durationMinutes,
      'p_end_time': endTime?.toUtc().toIso8601String(),
    });

    final rescheduled = CreateAppointmentResult.fromRpcData({
      ...?result.data,
      'appointment_id': result.data?['appointment_id'] ?? appointmentId,
      'type': AppointmentType.planned.wireValue,
      'status': AppointmentStatus.scheduled.wireValue,
    });
    if (rescheduled == null) {
      throw StateError('Reschedule appointment returned an unexpected shape.');
    }
    return rescheduled;
  }

  Future<AppointmentStatus> cancel({required String appointmentId, String? reason}) async {
    _assertNonEmpty('appointmentId', appointmentId);

    if (reason != null && reason.trim().length > 2000) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Cancel reason must be 2000 characters or fewer.',
        ),
      );
    }

    final result = await invokeRpc('cancel_appointment', {
      'p_appointment_id': appointmentId.trim(),
      if (reason != null && reason.trim().isNotEmpty) 'p_reason': reason.trim(),
    });

    final status = AppointmentStatus.tryParse(result.data?['status']?.toString());
    if (status == null) {
      throw StateError('Cancel appointment returned an unexpected shape.');
    }
    return status;
  }

  void _assertNonEmpty(String field, String value) {
    if (value.trim().isEmpty) {
      throw RpcFailure(RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: '$field is required.'));
    }
  }

  void _assertDurationMinutes(int minutes) {
    if (minutes < 5 || minutes > 240) {
      throw RpcFailure(
        const RpcResult(
          success: false,
          errorCode: 'INVALID_INPUT',
          errorMessage: 'Duration must be between 5 and 240 minutes.',
        ),
      );
    }
  }
}

final appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(supabaseClientProvider));
});
