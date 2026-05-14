import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/deployment_profile.dart';
import '../core/errors/failures.dart';
import '../core/widgets/app_loading_state.dart';
import '../shared/providers/startup_session_provider.dart';
import '../shared/services/startup_health_service.dart';

/// Central route names for the safe pre-auth startup shell.
abstract final class AppRoutes {
  static const startupEntry = '/';
  static const startupCheck = '/startup-check';
  static const setupGuidance = '/setup-guidance';
  static const protectedBlocked = '/protected-blocked';
  static const protectedPlaceholder = '/protected/dashboard';
  static const protectedPrefix = '/protected';
}

/// Rebuilds router redirects whenever startup session state changes.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshSignal = ValueNotifier<int>(0);
  ref.onDispose(refreshSignal.dispose);
  ref.listen<StartupSessionState>(startupSessionProvider, (_, _) {
    refreshSignal.value++;
  });

  final notifier = ref.read(startupSessionProvider.notifier);

  return GoRouter(
    initialLocation: AppRoutes.startupCheck,
    refreshListenable: refreshSignal,
    routes: [
      GoRoute(path: AppRoutes.startupCheck, builder: (context, state) => const _StartupCheckPage()),
      GoRoute(path: AppRoutes.startupEntry, builder: (context, state) => const _StartupEntryPage()),
      GoRoute(path: AppRoutes.setupGuidance, builder: (context, state) => const _SetupGuidancePage()),
      GoRoute(path: AppRoutes.protectedBlocked, builder: (context, state) => const _ProtectedRouteBlockedPage()),
      GoRoute(path: AppRoutes.protectedPlaceholder, builder: (context, state) => const _ProtectedPlaceholderPage()),
    ],
    redirect: (context, state) {
      final session = ref.read(startupSessionProvider);
      final location = state.matchedLocation;

      // Protected locations are intercepted before any screen can render.
      if (location.startsWith(AppRoutes.protectedPrefix)) {
        if (session.currentView != StartupCurrentView.protectedRouteBlocked) {
          notifier.blockProtectedRoute(location);
        }
        return AppRoutes.protectedBlocked;
      }

      // Non-protected routes follow the current startup state machine.
      return switch (session.currentView) {
        StartupCurrentView.startupCheck => location == AppRoutes.startupCheck ? null : AppRoutes.startupCheck,
        StartupCurrentView.setupGuidance => location == AppRoutes.setupGuidance ? null : AppRoutes.setupGuidance,
        StartupCurrentView.protectedRouteBlocked =>
          location == AppRoutes.protectedBlocked ? null : AppRoutes.protectedBlocked,
        StartupCurrentView.unauthenticatedEntry => location == AppRoutes.startupEntry ? null : AppRoutes.startupEntry,
      };
    },
  );
});

/// Splash-like page shown while configuration and connectivity are being checked.
class _StartupCheckPage extends StatelessWidget {
  const _StartupCheckPage();

  @override
  Widget build(BuildContext context) {
    return const _StartupScaffold(
      title: 'Starting clinic-local bootstrap',
      subtitle: 'AiClinic is validating the local deployment profile and probing shared backend services.',
      child: AppLoadingState(
        title: 'Checking startup requirements',
        message:
            'This safe pre-auth stage keeps protected routes blocked until configuration and connectivity are known.',
      ),
    );
  }
}

/// Main startup dashboard that surfaces configuration, health, and theme state.
class _StartupEntryPage extends ConsumerWidget {
  const _StartupEntryPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(startupSessionProvider);
    final notifier = ref.read(startupSessionProvider.notifier);

    return _StartupScaffold(
      title: 'AiClinic startup foundation',
      subtitle:
          'The bootstrap shell is ready for Phase 3 screens while already enforcing safe routing and visible connectivity status.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.failure != null) _FailureBanner(failure: session.failure!),
          // Show what configuration the app resolved during bootstrap.
          _StatusCard(
            title: 'Deployment profile',
            lines: [
              'Configuration: ${_configurationStatusLabel(session.configurationStatus)}',
              'Mode: ${session.deploymentProfile?.deploymentMode.wireValue ?? 'unknown'}',
              'Profile file: ${session.deploymentProfile?.sourcePath ?? DeploymentProfileStore.defaultFileName}',
              'Supabase URL: ${session.deploymentProfile?.supabaseUrl ?? 'unavailable'}',
            ],
          ),
          const SizedBox(height: 16),
          // Show the latest health probe results for the clinic-local services.
          _StatusCard(
            title: 'Clinic-local connectivity',
            lines: [
              'Status: ${_connectivityStatusLabel(session.connectivityStatus)}',
              if (session.lastHealthCheck != null) 'Last check: ${session.lastHealthCheck!.toLocal()}',
              if (session.blockedReason != null) session.blockedReason!,
              ...?session.healthResult?.checks.map(
                (check) => '${check.name}: ${check.detail ?? 'No detail'} (${check.uri})',
              ),
            ],
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
                  // Theme mode is switchable even before authenticated flows exist.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ThemeMode.values.map((themeMode) {
                      return ChoiceChip(
                        label: Text(_themeModeLabel(themeMode)),
                        selected: session.themeMode == themeMode,
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
                  // Re-run the full bootstrap flow without restarting the app.
                  await notifier.retryStartup();
                },
                child: const Text('Refresh startup checks'),
              ),
              OutlinedButton(
                onPressed: () {
                  // Intentionally exercises the route guard placeholder.
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

/// Guidance screen shown when the local deployment profile cannot be used safely.
class _SetupGuidancePage extends ConsumerWidget {
  const _SetupGuidancePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(startupSessionProvider);
    final notifier = ref.read(startupSessionProvider.notifier);

    return _StartupScaffold(
      title: 'Setup guidance required',
      subtitle: 'Startup stopped before protected use because the local deployment profile is missing or invalid.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.failure != null) _FailureBanner(failure: session.failure!),
          _StatusCard(
            title: 'Next step',
            lines: [
              'Create `${DeploymentProfileStore.defaultConfigDirectory}/${DeploymentProfileStore.defaultFileName}` when running from `frontend/`, use `frontend/lib/core/config/${DeploymentProfileStore.defaultFileName}` when running from the repository root, or set `${DeploymentProfileStore.environmentVariable}` to an absolute profile path.',
              'Required fields: deployment_mode=local, supabase_url, and supabase_anon_key.',
              'Optional field: ai_service_url remains non-blocking in V1-0.',
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                '{\n'
                '  "deployment_mode": "local",\n'
                '  "supabase_url": "http://192.168.1.100:54321",\n'
                '  "supabase_anon_key": "<anon-public-key>",\n'
                '  "ai_service_url": "http://192.168.1.100:8090"\n'
                '}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              // Lets the operator retry after fixing the local profile file.
              await notifier.retryStartup();
            },
            child: const Text('Retry bootstrap'),
          ),
        ],
      ),
    );
  }
}

/// Explanation screen used when someone tries to open a protected route too early.
class _ProtectedRouteBlockedPage extends ConsumerWidget {
  const _ProtectedRouteBlockedPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(startupSessionProvider);
    final notifier = ref.read(startupSessionProvider.notifier);

    return _StartupScaffold(
      title: 'Protected route blocked',
      subtitle:
          'The routing scaffold is working as intended: no protected destination can open before authenticated context exists.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusCard(
            title: 'Why you were redirected',
            lines: [
              session.blockedReason ?? 'Protected routes stay unavailable until authenticated flows are implemented.',
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              // Clear the temporary block message and return to the safe startup view.
              notifier.acknowledgeProtectedRouteBlock();
              context.go(AppRoutes.startupEntry);
            },
            child: const Text('Return to startup'),
          ),
        ],
      ),
    );
  }
}

/// Placeholder protected page that should only be reachable after future auth work.
class _ProtectedPlaceholderPage extends StatelessWidget {
  const _ProtectedPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('This route should never render before authentication.')));
  }
}

/// Shared page frame for the small set of startup shell screens.
class _StartupScaffold extends StatelessWidget {
  const _StartupScaffold({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable card for rendering labeled status lines in the startup UI.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line))),
          ],
        ),
      ),
    );
  }
}

/// Highlights configuration or connectivity failures without leaving the startup flow.
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.failure});

  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failure.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onErrorContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    failure.message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converts configuration state into human-readable UI copy.
String _configurationStatusLabel(StartupConfigurationStatus status) {
  return switch (status) {
    StartupConfigurationStatus.unknown => 'Unknown',
    StartupConfigurationStatus.valid => 'Valid',
    StartupConfigurationStatus.missing => 'Missing',
    StartupConfigurationStatus.invalid => 'Invalid',
  };
}

/// Converts connectivity state into human-readable UI copy.
String _connectivityStatusLabel(StartupConnectivityStatus status) {
  return switch (status) {
    StartupConnectivityStatus.unknown => 'Unknown',
    StartupConnectivityStatus.healthy => 'Healthy',
    StartupConnectivityStatus.degraded => 'Degraded',
    StartupConnectivityStatus.unreachable => 'Unreachable',
  };
}

/// Converts a Flutter theme mode into the label shown on the chips.
String _themeModeLabel(ThemeMode themeMode) {
  return switch (themeMode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
