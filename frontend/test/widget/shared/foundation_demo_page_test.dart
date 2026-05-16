import 'package:ai_clinic/app/theme/app_theme.dart';
import 'package:ai_clinic/features/foundation_demo/presentation/pages/foundation_demo_page.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/startup_test_support.dart';

class _DemoStartupSessionNotifier extends StartupSessionNotifier {
  @override
  StartupSessionState build() {
    return StartupSessionState(
      configurationStatus: StartupConfigurationStatus.valid,
      connectivityStatus: StartupConnectivityStatus.healthy,
      currentView: StartupCurrentView.unauthenticatedEntry,
      themeMode: ThemeMode.light,
      deploymentProfile: sampleDeploymentProfile(),
      healthResult: sampleHealthResult(),
      lastHealthCheck: sampleHealthResult().checkedAt,
    );
  }
}

void main() {
  group('FoundationDemoPage', () {
    testWidgets('renders shared foundation sections and actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [startupSessionProvider.overrideWith(() => _DemoStartupSessionNotifier())],
          child: MaterialApp(theme: AppTheme.lightTheme(), home: const FoundationDemoPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Shared foundations demo'), findsOneWidget);
      expect(find.textContaining('Theme: Light'), findsOneWidget);
      expect(find.textContaining('Connectivity: Healthy'), findsOneWidget);
      expect(find.text('Actions and forms'), findsOneWidget);
      expect(find.text('Sample table'), findsOneWidget);
      expect(find.text('Show snackbar'), findsOneWidget);
      expect(find.text('Connectivity issue'), findsOneWidget);
    });

    testWidgets('toggles loading state panel', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [startupSessionProvider.overrideWith(() => _DemoStartupSessionNotifier())],
          child: MaterialApp(theme: AppTheme.lightTheme(), home: const FoundationDemoPage()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Toggle loading'));
      await tester.pump();

      expect(find.text('Loading sample data'), findsOneWidget);
    });
  });
}
