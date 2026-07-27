import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/application/appointment_status_action_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';

/// Orchestrates multi-step appointment status transitions away from presentation widgets.
class AppointmentStatusService {
  const AppointmentStatusService(this._repository);

  final AppointmentRepository _repository;

  Future<AppointmentStatusActionResult> advanceStatus({
    required AppointmentDetail detail,
    required AppointmentStatus target,
    required String? selectedDoctorId,
  }) async {
    try {
      if (target == AppointmentStatus.inProgress) {
        final doctorId = selectedDoctorId?.trim();
        if (doctorId == null || doctorId.isEmpty) {
          return const AppointmentStatusActionFailed(
            'A doctor must be selected before starting this appointment.',
            doctorWasReassigned: false,
          );
        }

        var doctorWasReassigned = false;
        final assignedDoctorId = detail.doctorId?.trim();
        if (assignedDoctorId == null || assignedDoctorId.isEmpty || assignedDoctorId != doctorId) {
          await _repository.updateAppointment(
            appointmentId: detail.id,
            patientId: detail.patientId,
            doctorId: doctorId,
            startTime: detail.startTime,
            endTime: detail.endTime,
          );
          doctorWasReassigned = true;
        }

        try {
          final update = await _repository.updateAppointmentStatus(appointmentId: detail.id, newStatus: target);
          return AppointmentStatusActionSuccess(update.status);
        } on RpcFailure catch (error) {
          return AppointmentStatusActionFailed(
            appointmentMessageForRpc(error),
            doctorWasReassigned: doctorWasReassigned,
          );
        } catch (error, stack) {
          AppLog.warning('appointments.status_service.advance_status_failed reason=${error.runtimeType}');
          AppLog.fine('appointments.status_service.advance_status_failed.stack $stack');
          return AppointmentStatusActionFailed(
            'Could not update the appointment status. Please try again.',
            doctorWasReassigned: doctorWasReassigned,
          );
        }
      }

      final update = await _repository.updateAppointmentStatus(appointmentId: detail.id, newStatus: target);
      return AppointmentStatusActionSuccess(update.status);
    } on RpcFailure catch (error) {
      return AppointmentStatusActionFailed(appointmentMessageForRpc(error), doctorWasReassigned: false);
    } catch (error, stack) {
      AppLog.warning('appointments.status_service.advance_status_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.status_service.advance_status_failed.stack $stack');
      return const AppointmentStatusActionFailed(
        'Could not update the appointment status. Please try again.',
        doctorWasReassigned: false,
      );
    }
  }

  Future<AppointmentStatusActionResult> revertStatus({
    required String appointmentId,
    required AppointmentStatus target,
  }) async {
    try {
      final update = await _repository.updateAppointmentStatus(appointmentId: appointmentId, newStatus: target);
      return AppointmentStatusActionSuccess(update.status);
    } on RpcFailure catch (error) {
      return AppointmentStatusActionFailed(appointmentMessageForRpc(error), doctorWasReassigned: false);
    } catch (error, stack) {
      AppLog.warning('appointments.status_service.revert_status_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.status_service.revert_status_failed.stack $stack');
      return const AppointmentStatusActionFailed(
        'Could not revert the appointment status. Please try again.',
        doctorWasReassigned: false,
      );
    }
  }

  Future<AppointmentStatusActionResult> cancel({
    required String appointmentId,
    required String? reason,
  }) async {
    try {
      final status = await _repository.cancelAppointment(appointmentId: appointmentId, reason: reason);
      return AppointmentStatusActionSuccess(status);
    } on RpcFailure catch (error) {
      return AppointmentStatusActionFailed(appointmentMessageForRpc(error), doctorWasReassigned: false);
    } catch (error, stack) {
      AppLog.warning('appointments.status_service.cancel_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.status_service.cancel_failed.stack $stack');
      return const AppointmentStatusActionFailed(
        'Could not cancel the appointment. Please try again.',
        doctorWasReassigned: false,
      );
    }
  }

  Future<AppointmentStatusActionResult> markNoShow({required String appointmentId}) async {
    try {
      final status = await _repository.markAppointmentNoShow(appointmentId: appointmentId);
      return AppointmentStatusActionSuccess(status);
    } on RpcFailure catch (error) {
      return AppointmentStatusActionFailed(appointmentMessageForRpc(error), doctorWasReassigned: false);
    } catch (error, stack) {
      AppLog.warning('appointments.status_service.mark_no_show_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.status_service.mark_no_show_failed.stack $stack');
      return const AppointmentStatusActionFailed(
        'Could not mark the appointment as a no-show. Please try again.',
        doctorWasReassigned: false,
      );
    }
  }
}

final appointmentStatusServiceProvider = Provider<AppointmentStatusService>((ref) {
  return AppointmentStatusService(ref.watch(appointmentRepositoryProvider));
});
