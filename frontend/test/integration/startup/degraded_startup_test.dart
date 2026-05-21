import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/testing/startup_test_support.dart';

void main() {
  testWidgets('keeps the entry experience visible when clinic-local services are unreachable', (tester) async {
    await pumpStartupApp(tester, healthResult: sampleHealthResult(status: StartupConnectivityStatus.unreachable));
    await completeStartupBootstrap(tester);

    expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
    expect(find.text('Clinic-local services unreachable'), findsOneWidget);
    expect(find.textContaining('Status: Unreachable'), findsOneWidget);
    expect(find.text('Try a protected route'), findsOneWidget);
  });

  testWidgets('auth 502 with api up is unreachable not falsely degraded', (tester) async {
    final checks = [
      StartupDependencyCheck(
        name: 'api',
        uri: Uri.parse('http://127.0.0.1:54321/rest/v1/'),
        reachable: true,
        statusCode: 200,
      ),
      StartupDependencyCheck(
        name: 'auth',
        uri: Uri.parse('http://127.0.0.1:54321/auth/v1/health'),
        reachable: false,
        statusCode: 502,
        detail: 'HTTP 502',
      ),
    ];
    final health = StartupHealthResult(
      status: classifyStartupConnectivity(checks),
      checkedAt: DateTime(2026, 5, 21),
      checks: checks,
    );

    await pumpStartupApp(tester, healthResult: health);
    await completeStartupBootstrap(tester);

    expect(find.text('Clinic-local services unreachable'), findsOneWidget);
    expect(find.text('Degraded clinic-local startup'), findsNothing);
    expect(find.textContaining('Status: Unreachable'), findsOneWidget);
  });

  testWidgets('shows degraded messaging when only part of the local stack responds', (tester) async {
    await pumpStartupApp(tester, healthResult: sampleHealthResult(status: StartupConnectivityStatus.degraded));
    await completeStartupBootstrap(tester);

    expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
    expect(find.text('Degraded clinic-local startup'), findsOneWidget);
    expect(find.textContaining('Status: Degraded'), findsOneWidget);
  });

  testWidgets('routes missing configuration to setup guidance', (tester) async {
    await pumpStartupApp(
      tester,
      profileError: const MissingDeploymentProfileException('No deployment profile was found for tests.'),
    );
    await completeStartupBootstrap(tester);

    expect(find.text('Setup guidance required'), findsOneWidget);
    expect(find.text('Retry bootstrap'), findsOneWidget);
    expect(find.textContaining('deployment-profile.json'), findsWidgets);
  });
}
