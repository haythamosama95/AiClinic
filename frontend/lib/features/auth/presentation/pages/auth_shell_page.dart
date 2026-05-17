import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Placeholder authenticated shell (full shell in US3).
class AuthShellPage extends ConsumerWidget {
  const AuthShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider).context;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AiClinic'),
        actions: [
          TextButton(onPressed: () => ref.read(authSessionProvider.notifier).signOut(), child: const Text('Sign out')),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            auth == null
                ? 'Loading session context…'
                : 'Signed in as ${auth.staffProfile.fullName} (${auth.staffProfile.role.wireValue}). '
                      'Operational modules will appear here in later features.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
