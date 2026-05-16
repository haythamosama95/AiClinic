import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../providers/startup_notifier.dart';
import '../widgets/connection_status_card.dart';
import '../widgets/degraded_state_notice.dart';
import '../widgets/failure_banner.dart';
import '../widgets/startup_scaffold.dart';

/// Main pre-auth entry experience with connection status and safe next-step guidance.
class StartupEntryPage extends ConsumerWidget {
  const StartupEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupNotifierProvider);
    final notifier = ref.read(startupNotifierProvider.notifier);

    return StartupScaffold(
      title: 'AiClinic clinic-local startup',
      subtitle:
          'Review configuration and connectivity before authenticated workflows are introduced in later features.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (startup.showDegradedNotice)
            DegradedStateNotice(connectivityStatus: startup.connectivityStatus, message: startup.failure?.message),
          if (startup.failure != null && startup.showConnectivityFailure) FailureBanner(failure: startup.failure!),
          ConnectionStatusCard(title: 'Deployment profile', lines: startup.deploymentProfileLines),
          const SizedBox(height: 16),
          ConnectionStatusCard(title: 'Clinic-local connectivity', lines: startup.connectivityLines),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next steps', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const Text(
                    'Confirm the deployment profile points at the receptionist server node, verify connectivity above, '
                    'then continue with workstation setup documentation before patient or billing workflows are added.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme foundation', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ThemeMode.values.map((themeMode) {
                      return ChoiceChip(
                        label: Text(themeModeLabel(themeMode)),
                        selected: startup.themeMode == themeMode,
                        onSelected: (_) => notifier.setThemeMode(themeMode),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () async {
                  await notifier.retryStartup();
                },
                child: const Text('Refresh startup checks'),
              ),
              OutlinedButton(
                onPressed: () {
                  context.go(AppRoutes.protectedPlaceholder);
                },
                child: const Text('Try a protected route'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
