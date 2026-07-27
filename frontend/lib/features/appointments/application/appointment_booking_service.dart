import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';

/// Outcome of a booking create or update RPC.
sealed class AppointmentBookingResult {
  const AppointmentBookingResult();
}

final class AppointmentBookingSuccess extends AppointmentBookingResult {
  const AppointmentBookingSuccess();
}

final class AppointmentBookingFailure extends AppointmentBookingResult {
  const AppointmentBookingFailure(
    this.userMessage, {
    this.isScheduleConflict = false,
  });

  final String userMessage;
  final bool isScheduleConflict;
}

/// Wraps appointment create/update RPCs and maps failures to user-facing copy.
class AppointmentBookingService {
  const AppointmentBookingService(this._repository);

  final AppointmentRepository _repository;

  Future<AppointmentBookingResult> createAppointment({
    required String branchId,
    required String patientId,
    String? doctorId,
    required AppointmentType type,
    required DateTime startTime,
    required int durationMinutes,
    String? notes,
  }) async {
    try {
      await _repository.createAppointment(
        branchId: branchId,
        patientId: patientId,
        doctorId: doctorId,
        type: type,
        startTime: startTime,
        durationMinutes: durationMinutes,
        notes: notes,
      );
      return const AppointmentBookingSuccess();
    } on RpcFailure catch (error) {
      return AppointmentBookingFailure(
        appointmentMessageForRpc(error),
        isScheduleConflict: error.code == 'SCHEDULE_CONFLICT',
      );
    } catch (error) {
      return AppointmentBookingFailure(appointmentMessageForError(error));
    }
  }

  Future<AppointmentBookingResult> updateAppointment({
    required String appointmentId,
    required String patientId,
    String? doctorId,
    required String branchId,
    required DateTime startTime,
    required int durationMinutes,
    String? notes,
  }) async {
    try {
      await _repository.updateAppointment(
        appointmentId: appointmentId,
        patientId: patientId,
        doctorId: doctorId,
        branchId: branchId,
        startTime: startTime,
        durationMinutes: durationMinutes,
        notes: notes,
      );
      return const AppointmentBookingSuccess();
    } on RpcFailure catch (error) {
      return AppointmentBookingFailure(
        appointmentMessageForRpc(error),
        isScheduleConflict: error.code == 'SCHEDULE_CONFLICT',
      );
    } catch (error) {
      return AppointmentBookingFailure(appointmentMessageForError(error));
    }
  }
}

final appointmentBookingServiceProvider = Provider<AppointmentBookingService>((ref) {
  return AppointmentBookingService(ref.watch(appointmentRepositoryProvider));
});
