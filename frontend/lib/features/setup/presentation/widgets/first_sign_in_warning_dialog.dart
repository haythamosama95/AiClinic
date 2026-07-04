import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';

/// Prominent shipped-password warning for the bootstrap administrator.
abstract final class FirstSignInWarningDialog {
  const FirstSignInWarningDialog._();

  /// Shows a non-dismissible dialog urging the bootstrap admin to change the default password.
  static Future<void> show(BuildContext context, {required VoidCallback onContinue}) {
    return showAppDialog<void>(
      context,
      barrierDismissible: false,
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Change the default password',
          body: Text(
            'This installation uses a shipped administrator password intended for first setup only. '
            'Change it when your clinic network is ready. You can continue with setup now and change the password later from clinic administration.',
            style: dialogContext.typography.body.copyWith(color: dialogContext.colors.textSecondary),
          ),
          footer: AppButton(
            label: 'Continue to clinic setup',
            onPressed: () async {
              await close();
              onContinue();
            },
          ),
        );
      },
    );
  }
}
