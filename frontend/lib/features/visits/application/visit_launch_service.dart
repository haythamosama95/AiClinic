import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';

/// Outcome of opening or creating a visit for an appointment.
sealed class VisitLaunchResult {
  const VisitLaunchResult();
}

/// Visit is ready to open in the documentation workflow.
final class VisitLaunchSuccess extends VisitLaunchResult {
  const VisitLaunchSuccess(this.visitId);

  final String visitId;
}

/// Visit could not be opened; [userMessage] is safe to show in a toast.
final class VisitLaunchFailed extends VisitLaunchResult {
  const VisitLaunchFailed(this.userMessage);

  final String userMessage;
}

/// Single entry point for opening visit documentation from an appointment.
class VisitLaunchService {
  const VisitLaunchService(this._repository);

  final VisitRepository _repository;

  Future<VisitLaunchResult> openOrCreateVisitForAppointment({
    required String appointmentId,
    required String? doctorId,
  }) async {
    try {
      final link = await _repository.getVisitByAppointment(appointmentId: appointmentId);
      var visitId = link.visitId?.trim();

      if (visitId == null || visitId.isEmpty) {
        final created = await _repository.createVisit(appointmentId: appointmentId, doctorId: doctorId);
        visitId = created.visitId.trim();
      }

      if (visitId.isEmpty) {
        return const VisitLaunchFailed('Could not open the visit. Please try again.');
      }

      return VisitLaunchSuccess(visitId);
    } on RpcFailure catch (error) {
      if (error.code == 'VISIT_ALREADY_EXISTS') {
        return _openExistingVisit(appointmentId);
      }
      return VisitLaunchFailed(visitMessageForRpc(error));
    } catch (_) {
      return const VisitLaunchFailed('Could not open the visit. Please try again.');
    }
  }

  Future<VisitLaunchResult> _openExistingVisit(String appointmentId) async {
    try {
      final link = await _repository.getVisitByAppointment(appointmentId: appointmentId);
      final visitId = link.visitId?.trim();
      if (visitId == null || visitId.isEmpty) {
        return const VisitLaunchFailed('Could not open the visit. Please try again.');
      }
      return VisitLaunchSuccess(visitId);
    } on RpcFailure catch (error) {
      return VisitLaunchFailed(visitMessageForRpc(error));
    } catch (_) {
      return const VisitLaunchFailed('Could not open the visit. Please try again.');
    }
  }
}

final visitLaunchServiceProvider = Provider<VisitLaunchService>((ref) {
  return VisitLaunchService(ref.watch(visitRepositoryProvider));
});
