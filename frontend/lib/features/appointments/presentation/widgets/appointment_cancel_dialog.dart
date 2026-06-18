import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Confirms cancellation of an appointment with an optional reason.
class AppointmentCancelDialog extends StatefulWidget {
  const AppointmentCancelDialog({
    required this.patientName,
    required this.dialogStyle,
    required this.animation,
    super.key,
  });

  final String patientName;
  final FDialogStyle dialogStyle;
  final Animation<double> animation;

  static Future<String?> show(BuildContext context, {required String patientName}) {
    final fTheme = context.theme;

    return showFDialog<String?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext, style, animation) {
        return FTheme(
          data: fTheme,
          child: AppointmentCancelDialog(patientName: patientName, dialogStyle: style, animation: animation),
        );
      },
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
    Navigator.of(context, rootNavigator: true).pop(_reasonController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return FDialog(
      style: widget.dialogStyle,
      animation: widget.animation,
      direction: Axis.horizontal,
      title: Text('Cancel appointment?', style: theme.textTheme.titleLarge),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.patientName} will be removed from the schedule. This cannot be undone.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SpacingTokens.md),
          AppTextField(
            key: const Key('appointment_cancel_reason'),
            controller: _reasonController,
            label: 'Reason (optional)',
            hintText: 'e.g. Patient requested',
            maxLines: 3,
          ),
          const SizedBox(height: SpacingTokens.xs),
          Text(
            'Staff and the patient record will see this reason.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
          ),
        ],
      ),
      actions: [
        AppButton(
          key: const Key('appointment_cancel_confirm'),
          label: 'Cancel appointment',
          variant: AppButtonVariant.destructive,
          onPressed: _confirm,
        ),
        AppButton(
          label: 'Keep appointment',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }
}
