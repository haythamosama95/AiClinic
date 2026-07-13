import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Confirms cancellation of an appointment with an optional reason (V1-4 US7).
class AppointmentCancelDialog extends StatefulWidget {
  const AppointmentCancelDialog({required this.appointment, super.key});

  final AppointmentListItem appointment;

  /// Returns the optional cancel reason when confirmed, or `null` when dismissed.
  static Future<String?> show(BuildContext context, {required AppointmentListItem appointment}) {
    return AppDialog.show<String?>(
      context,
      title: 'Cancel appointment?',
      description: 'Cancel ${appointment.patientName}\'s visit? The time slot will become available again.',
      size: AppDialogSize.sm,
      child: AppointmentCancelDialog(appointment: appointment),
    );
  }

  @override
  State<AppointmentCancelDialog> createState() => _AppointmentCancelDialogState();
}

class _AppointmentCancelDialogState extends State<AppointmentCancelDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop(_reasonController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFormField(
          id: 'cancel-reason',
          label: 'Reason (optional)',
          child: AppTextarea(
            controller: _reasonController,
            placeholder: 'e.g. Patient called to reschedule',
            rows: 3,
            maxLength: 2000,
            showCounter: true,
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Keep appointment'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(variant: AppButtonVariant.danger, onPressed: _confirm, child: const Text('Cancel appointment')),
          ],
        ),
      ],
    );
  }
}
