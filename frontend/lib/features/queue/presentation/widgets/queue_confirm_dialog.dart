import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Danger confirmation kind for queue row actions (web `ConfirmDialog`).
enum QueueConfirmKind { cancel, noShow }

/// Danger confirm modal for cancel / no-show transitions (web `ConfirmDialog`).
class QueueConfirmDialog extends StatelessWidget {
  const QueueConfirmDialog({
    required this.open,
    required this.kind,
    required this.patientName,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final bool open;
  final QueueConfirmKind kind;
  final String patientName;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  String get _title => switch (kind) {
    QueueConfirmKind.noShow => 'Mark as no show?',
    QueueConfirmKind.cancel => 'Cancel appointment?',
  };

  String get _confirmLabel => switch (kind) {
    QueueConfirmKind.noShow => 'Mark no show',
    QueueConfirmKind.cancel => 'Cancel appointment',
  };

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      open: open,
      onOpenChange: (next) {
        if (!next) {
          onCancel();
        }
      },
      title: _title,
      description: '$patientName — this action requires confirmation.',
      size: AppDialogSize.sm,
      showCloseButton: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: onCancel,
            child: const Text('Go back'),
          ),
          const SizedBox(width: AppSpacing.space2),
          AppButton(
            variant: AppButtonVariant.danger,
            onPressed: onConfirm,
            child: Text(_confirmLabel),
          ),
        ],
      ),
    );
  }
}
