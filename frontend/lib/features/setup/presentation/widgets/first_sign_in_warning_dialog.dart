import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Prominent shipped-password warning for the bootstrap administrator (FR-first sign-in).
class FirstSignInWarningDialog extends StatelessWidget {
  const FirstSignInWarningDialog({required this.onContinue, super.key});

  final VoidCallback onContinue;

  static Future<void> show(BuildContext context, {required VoidCallback onContinue}) {
    return AppDialog.show<void>(
      context: context,
      title: 'Change the default password',
      barrierDismissible: false,
      body: const Text(
        'This installation uses a shipped administrator password intended for first setup only. '
        'Change it when your clinic network is ready. You can continue with setup now and change the password later from clinic administration.',
      ),
      actions: [
        AppButton(
          label: 'Continue to clinic setup',
          onPressed: () {
            Navigator.of(context).pop();
            onContinue();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
