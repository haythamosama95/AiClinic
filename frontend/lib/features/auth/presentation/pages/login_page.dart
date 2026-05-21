import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';

/// Staff email/password sign-in for clinic workstations.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await ref
        .read(authNotifierProvider.notifier)
        .signIn(email: _emailController.text, password: _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final authUi = ref.watch(authNotifierProvider);
    final session = ref.watch(authSessionProvider);
    final startup = ref.watch(startupSessionProvider);
    final supabaseReady = startup.configurationStatus == StartupConfigurationStatus.valid && SupabaseBootstrap.isReady;
    final isBusy = authUi.isSubmitting || session.status == AuthSessionStatus.loading || !supabaseReady;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Sign in with your clinic staff account', style: Theme.of(context).textTheme.titleMedium),
                  if (!supabaseReady) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text('Preparing clinic sign-in services…', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 20),
                  if (authUi.errorMessage != null) ...[
                    MaterialBanner(
                      content: Text(authUi.errorMessage!),
                      leading: const Icon(Icons.error_outline),
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      actions: [
                        TextButton(
                          onPressed: isBusy ? null : () => ref.read(authNotifierProvider.notifier).clearError(),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    enabled: !isBusy,
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty || !trimmed.contains('@')) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    enabled: !isBusy,
                    onFieldSubmitted: (_) => isBusy ? null : _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: isBusy ? null : _submit,
                    child: isBusy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: isBusy ? null : () => context.go(AppRoutes.forgotPassword),
                    child: const Text('Forgot password?'),
                  ),
                  TextButton(
                    onPressed: isBusy ? null : () => context.go(AppRoutes.startupEntry),
                    child: const Text('Back to startup'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
