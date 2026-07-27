import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';

/// Loads a full appointment profile for the detail view (`get_appointment` RPC).
final appointmentDetailProvider = FutureProvider.autoDispose.family<AppointmentDetail, String>((
  ref,
  appointmentId,
) async {
  final canAccess = ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessAppointmentHub));
  if (!canAccess) {
    throw RpcFailure(
      const RpcResult(success: false, errorCode: 'PERMISSION_DENIED', errorMessage: 'Permission denied.'),
    );
  }

  return ref.read(appointmentRepositoryProvider).getAppointment(appointmentId: appointmentId);
});
