import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/provisioning_rules.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_fill_dummy_clinic_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_reset_clinic_button.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:go_router/go_router.dart';

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
          const DevFillDummyClinicButton(),
          const DevResetClinicButton(),
          TextButton(onPressed: () => ref.read(authSessionProvider.notifier).signOut(), child: const Text('Sign out')),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                auth == null
                    ? 'Loading session context…'
                    : 'Signed in as ${auth.staffProfile.fullName} (${auth.staffProfile.role.wireValue}). '
                          'Operational modules will appear here in later features.',
                textAlign: TextAlign.center,
              ),
              if (auth != null && !auth.setupRequired) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: () => context.go(AppRoutes.settings), child: const Text('Settings')),
              ],
              if (auth != null && !auth.setupRequired && ProvisioningRules.canProvisionStaff(auth.staffProfile)) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.staffCreate),
                  child: const Text('Create staff account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
