import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/errors/failures.dart';
import 'package:ai_clinic/features/startup/presentation/pages/startup_entry_page.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/startup_test_support.dart';

class _HealthyStartupSessionNotifier extends StartupSessionNotifier {
  _HealthyStartupSessionNotifier(this.profile, this.health);

  final DeploymentProfile profile;
  final StartupHealthResult health;

  @override
  StartupSessionState build() {
    return StartupSessionState(
      configurationStatus: StartupConfigurationStatus.valid,
      connectivityStatus: StartupConnectivityStatus.healthy,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.system,
      deploymentProfile: profile,
      healthResult: health,
      lastHealthCheck: health.checkedAt,
    );
  }
}

class _DegradedStartupSessionNotifier extends StartupSessionNotifier {
  _DegradedStartupSessionNotifier(this.health);

  final StartupHealthResult health;

  @override
  StartupSessionState build() {
    return StartupSessionState(
      configurationStatus: StartupConfigurationStatus.valid,
      connectivityStatus: StartupConnectivityStatus.degraded,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.system,
      deploymentProfile: sampleDeploymentProfile(),
      failure: ConnectivityFailure(health.userMessage),
      healthResult: health,
      blockedReason: health.userMessage,
      lastHealthCheck: health.checkedAt,
    );
  }
}

void main() {
  group('StartupEntryPage', () {
    testWidgets('shows deployment profile and healthy connectivity details', (tester) async {
      final profile = sampleDeploymentProfile(sourcePath: 'widget-test/profile.json');
      final health = sampleHealthResult();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [startupSessionProvider.overrideWith(() => _HealthyStartupSessionNotifier(profile, health))],
          child: const MaterialApp(home: StartupEntryPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
      expect(find.text('Deployment profile'), findsOneWidget);
      expect(find.text('Clinic-local connectivity'), findsOneWidget);
      expect(find.textContaining('Configuration: Valid'), findsOneWidget);
      expect(find.textContaining('Status: Healthy'), findsOneWidget);
      expect(find.textContaining('Supabase URL: ${profile.supabaseUrl}'), findsOneWidget);
      expect(find.text('Next steps'), findsOneWidget);
      expect(find.text('Refresh startup checks'), findsOneWidget);
    });

    testWidgets('shows degraded notice when connectivity is not fully healthy', (tester) async {
      final health = sampleHealthResult(status: StartupConnectivityStatus.degraded);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [startupSessionProvider.overrideWith(() => _DegradedStartupSessionNotifier(health))],
          child: const MaterialApp(home: StartupEntryPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Degraded clinic-local startup'), findsOneWidget);
      expect(find.textContaining('Status: Degraded'), findsOneWidget);
    });
  });
}
