import 'package:flutter/material.dart';

/// Prominent shipped-password warning for the bootstrap administrator (FR-first sign-in).
class FirstSignInWarningDialog extends StatelessWidget {
  const FirstSignInWarningDialog({super.key, required this.onContinue});

  final VoidCallback onContinue;

  static Future<void> show(BuildContext context, {required VoidCallback onContinue}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FirstSignInWarningDialog(onContinue: onContinue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded),
      title: const Text('Change the default password'),
      content: const Text(
        'This installation uses a shipped administrator password intended for first setup only. '
        'Change it when your clinic network is ready. You can continue with setup now and change the password later from clinic administration.',
      ),
      actions: [FilledButton(onPressed: onContinue, child: const Text('Continue to clinic setup'))],
    );
  }
}
