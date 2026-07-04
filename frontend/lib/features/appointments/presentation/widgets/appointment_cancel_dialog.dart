import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

/// Confirms cancellation of an appointment with an optional reason.
Future<String?> showAppointmentCancelDialog(
  BuildContext context, {
  required String patientName,
}) {
  return showAppDialog<String>(
    context,
    size: AppDialogSize.sm,
    barrierDismissible: false,
    semanticLabel: 'Cancel appointment',
    builder: (dialogContext, close) {
      return _AppointmentCancelDialogContent(
        patientName: patientName,
        onClose: () => close(),
        onConfirm: (reason) => close(reason),
      );
    },
  );
}

class _AppointmentCancelDialogContent extends StatefulWidget {
  const _AppointmentCancelDialogContent({
    required this.patientName,
    required this.onClose,
    required this.onConfirm,
  });

  final String patientName;
  final VoidCallback onClose;
  final ValueChanged<String> onConfirm;

  @override
  State<_AppointmentCancelDialogContent> createState() => _AppointmentCancelDialogContentState();
}

class _AppointmentCancelDialogContentState extends State<_AppointmentCancelDialogContent> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Cancel appointment?',
      description: '${widget.patientName} will be removed from the schedule. This cannot be undone.',
      onClose: widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormField(
            label: 'Reason (optional)',
            helperText: 'Staff and the patient record will see this reason.',
            child: AppTextField(
              key: const Key('appointment_cancel_reason'),
              controller: _reasonController,
              hintText: 'e.g. Patient requested',
              maxLines: 3,
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Keep appointment',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            key: const Key('appointment_cancel_confirm'),
            label: 'Cancel appointment',
            variant: AppButtonVariant.danger,
            onPressed: () => widget.onConfirm(_reasonController.text.trim()),
          ),
        ],
      ),
    );
  }
}
