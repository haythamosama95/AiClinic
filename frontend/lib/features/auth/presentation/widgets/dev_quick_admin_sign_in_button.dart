import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

const kDevAdminUsername = String.fromEnvironment('DEV_ADMIN_USER', defaultValue: '');
const kDevAdminPassword = String.fromEnvironment('DEV_ADMIN_PASS', defaultValue: '');

/// Debug-only one-tap sign-in as the seeded bootstrap administrator.
class DevQuickAdminSignInButton extends ConsumerWidget {
  const DevQuickAdminSignInButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    if (kDevAdminUsername.isEmpty || kDevAdminPassword.isEmpty) {
      return const SizedBox.shrink();
    }

    final authUi = ref.watch(authNotifierProvider);
    final session = ref.watch(authSessionProvider);
    final startup = ref.watch(startupSessionProvider);
    final supabaseReady = startup.configurationStatus == StartupConfigurationStatus.valid && SupabaseBootstrap.isReady;
    final isBusy = authUi.isSubmitting || session.status == AuthSessionStatus.loading || !supabaseReady;

    return TextButton.icon(
      onPressed: isBusy
          ? null
          : () => ref
                .read(authNotifierProvider.notifier)
                .signIn(username: kDevAdminUsername, password: kDevAdminPassword),
      icon: const Icon(Icons.developer_mode),
      label: const Text('Dev: sign in as admin'),
    );
  }
}
