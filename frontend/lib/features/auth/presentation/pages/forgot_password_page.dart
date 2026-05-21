import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';

/// Forgot-password path (US7): administrator-mediated recovery only — no self-service reset.
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_reset_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'Password recovery is administrator-mediated',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'AiClinic does not offer self-service password reset. Contact your clinic owner or administrator '
                  'to set a new password for your staff account.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'If you are the clinic administrator, sign in with an owner or administrator account and use '
                  'Reset staff password from the home screen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),
                FilledButton(onPressed: () => context.go(AppRoutes.login), child: const Text('Back to sign in')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
