import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';

/// Post-login clinic workstation settings (session policies, etc.).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idleSettings = ref.watch(idleTimeoutSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.home)),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Workstation', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          idleSettings.when(
            data: (settings) => ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Idle sign-out'),
              subtitle: Text(
                'Automatically sign out after ${IdleTimeoutConfig.formatDuration(settings.duration)} without keyboard or pointer input.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.settingsIdleTimeout),
            ),
            loading: () => const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('Idle sign-out'),
              subtitle: Text('Loading…'),
            ),
            error: (_, _) => ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Idle sign-out'),
              subtitle: const Text('Could not load current value'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.settingsIdleTimeout),
            ),
          ),
        ],
      ),
    );
  }
}
