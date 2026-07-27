import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';

/// Outcome of a calendar reschedule RPC.
sealed class AppointmentRescheduleResult {
  const AppointmentRescheduleResult();
}

final class AppointmentRescheduleSuccess extends AppointmentRescheduleResult {
  const AppointmentRescheduleSuccess();
}

final class AppointmentRescheduleFailure extends AppointmentRescheduleResult {
  const AppointmentRescheduleFailure(this.userMessage);

  final String userMessage;
}

/// Wraps appointment reschedule RPC and maps failures to user-facing copy.
class AppointmentRescheduleService {
  const AppointmentRescheduleService(this._repository);

  final AppointmentRepository _repository;

  Future<AppointmentRescheduleResult> reschedule({
    required String appointmentId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      await _repository.rescheduleAppointment(
        appointmentId: appointmentId,
        startTime: startTime,
        endTime: endTime,
      );
      return const AppointmentRescheduleSuccess();
    } on RpcFailure catch (error) {
      return AppointmentRescheduleFailure(appointmentMessageForRpc(error));
    } catch (error, stack) {
      AppLog.warning('appointments.reschedule.reschedule_failed reason=${error.runtimeType}');
      AppLog.fine('appointments.reschedule.reschedule_failed.stack $stack');
      return const AppointmentRescheduleFailure(
        'Could not update the appointment. Please try again.',
      );
    }
  }
}

final appointmentRescheduleServiceProvider = Provider<AppointmentRescheduleService>((ref) {
  return AppointmentRescheduleService(ref.watch(appointmentRepositoryProvider));
});
