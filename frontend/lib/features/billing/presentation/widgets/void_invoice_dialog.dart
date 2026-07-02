import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Void invoice dialog with mandatory reason (V1-6 US6).
abstract final class VoidInvoiceDialog {
  static Future<String?> show(BuildContext context) {
    final reasonController = TextEditingController();

    return AppDialog.show<String>(
      context: context,
      title: 'Void invoice',
      barrierDismissible: false,
      bodyBuilder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Voiding locks this invoice. Payments cannot be recorded afterward. This action is audited.'),
          const SizedBox(height: SpacingTokens.md),
          AppTextField(controller: reasonController, label: 'Reason', hintText: 'Why is this invoice being voided?'),
        ],
      ),
      actionsBuilder: (dialogContext) => [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.outline,
          expand: false,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        AppButton(
          label: 'Void invoice',
          variant: AppButtonVariant.destructive,
          expand: false,
          onPressed: () {
            final reason = reasonController.text.trim();
            if (reason.isEmpty) {
              return;
            }
            Navigator.of(dialogContext).pop(reason);
          },
        ),
      ],
    );
  }
}
