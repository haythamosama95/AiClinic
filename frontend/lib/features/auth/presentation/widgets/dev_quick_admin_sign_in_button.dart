import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';

/// Local seed admin from [20260516100400_auth_rbac_seed.sql] (`admin` / `admin`).
const kDevAdminUsername = 'admin';
const kDevAdminPassword = 'admin';

/// Debug-only one-tap sign-in as the seeded bootstrap administrator.
class DevQuickAdminSignInButton extends ConsumerWidget {
  const DevQuickAdminSignInButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final authUi = ref.watch(authNotifierProvider);
    final isBusy = authUi.isSubmitting;

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
