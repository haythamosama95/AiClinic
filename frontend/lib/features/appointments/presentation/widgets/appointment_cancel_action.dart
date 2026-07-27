import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_status_action_result.dart';
import 'package:ai_clinic/features/appointments/application/appointment_status_service.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';

/// Shows the cancel dialog, calls [appointmentStatusServiceProvider], and toasts the result.
///
/// Returns `true` when the appointment was cancelled successfully.
Future<bool> runAppointmentCancelFlow(
  BuildContext context,
  WidgetRef ref,
  AppointmentListItem item, {
  VoidCallback? onSuccess,
  String? successMessage,
}) async {
  final reason = await AppointmentCancelDialog.show(context, appointment: item);
  if (reason == null || !context.mounted) {
    return false;
  }

  final result = await ref
      .read(appointmentStatusServiceProvider)
      .cancel(appointmentId: item.id, reason: reason.isEmpty ? null : reason);

  if (!context.mounted) {
    return false;
  }

  switch (result) {
    case AppointmentStatusActionSuccess():
      onSuccess?.call();
      appToast(
        context,
        AppToastInput(
          message: successMessage ?? '${item.patientName}\'s appointment was cancelled.',
          variant: AppToastVariant.success,
        ),
      );
      return true;
    case AppointmentStatusActionFailed(:final userMessage):
      appToast(context, AppToastInput(message: userMessage, variant: AppToastVariant.danger));
      return false;
  }
}
