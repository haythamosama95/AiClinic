import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';

const bool _kEnableDevTools = bool.fromEnvironment('ENABLE_DEV_TOOLS');

const _kDevAdminUsernameEnv = String.fromEnvironment('DEV_ADMIN_USER', defaultValue: '');
const _kDevAdminPasswordEnv = String.fromEnvironment('DEV_ADMIN_PASS', defaultValue: '');

/// Seeded bootstrap admin from [20260516100400_auth_rbac_seed.sql] (username migration: `admin`).
const _kDebugBootstrapAdminUsername = 'admin';
const _kDebugBootstrapAdminPassword = 'admin';

/// Resolves dev admin credentials: `--dart-define` overrides, else bootstrap seed in debug only.
({String username, String password}) _resolveDevAdminCredentials() {
  if (_kDevAdminUsernameEnv.isNotEmpty && _kDevAdminPasswordEnv.isNotEmpty) {
    return (username: _kDevAdminUsernameEnv, password: _kDevAdminPasswordEnv);
  }
  if (kDebugMode) {
    return (username: _kDebugBootstrapAdminUsername, password: _kDebugBootstrapAdminPassword);
  }
  return (username: '', password: '');
}

/// Debug-only one-tap sign-in as the seeded bootstrap administrator.
class DevQuickAdminSignInButton extends ConsumerWidget {
  const DevQuickAdminSignInButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode && !_kEnableDevTools) {
      return const SizedBox.shrink();
    }

    final credentials = _resolveDevAdminCredentials();
    if (credentials.username.isEmpty || credentials.password.isEmpty) {
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
                .signIn(username: credentials.username, password: credentials.password),
      icon: const Icon(Icons.developer_mode),
      label: const Text('Dev: sign in as admin'),
    );
  }
}
