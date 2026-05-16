import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/features/startup/presentation/providers/startup_notifier.dart';
import 'package:ai_clinic/features/startup/presentation/widgets/failure_banner.dart';
import 'package:ai_clinic/features/startup/presentation/widgets/startup_scaffold.dart';

const _kSetupGuidanceExampleJson =
    '{\n'
    '  "deployment_mode": "local",\n'
    '  "supabase_url": "http://192.168.1.100:54321",\n'
    '  "supabase_anon_key": "<anon-public-key>",\n'
    '  "ai_service_url": "http://192.168.1.100:8090"\n'
    '}';

/// Guidance screen shown when the local deployment profile cannot be used safely.
class SetupGuidancePage extends ConsumerWidget {
  const SetupGuidancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupNotifierProvider);
    final notifier = ref.read(startupNotifierProvider.notifier);

    return StartupScaffold(
      title: 'Setup guidance required',
      subtitle: 'Startup stopped before protected use because the local deployment profile is missing or invalid.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (startup.failure != null) FailureBanner(failure: startup.failure!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next step', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(
                    'Create `${DeploymentProfileStore.fileName}` in the process working directory (for example `frontend/${DeploymentProfileStore.fileName}` when running the app from `frontend/`).',
                  ),
                  const SizedBox(height: 8),
                  const Text('Required fields: deployment_mode=local, supabase_url, and supabase_anon_key.'),
                  const SizedBox(height: 8),
                  const Text('Optional field: ai_service_url remains non-blocking in V1-0.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                _kSetupGuidanceExampleJson,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await notifier.retryStartup();
            },
            child: const Text('Retry bootstrap'),
          ),
        ],
      ),
    );
  }
}
