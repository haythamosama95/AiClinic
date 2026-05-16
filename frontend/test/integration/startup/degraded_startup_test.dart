import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/startup_test_support.dart';

void main() {
  testWidgets('keeps the entry experience visible when clinic-local services are unreachable', (tester) async {
    await pumpStartupApp(tester, healthResult: sampleHealthResult(status: StartupConnectivityStatus.unreachable));
    await completeStartupBootstrap(tester);

    expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
    expect(find.text('Clinic-local services unreachable'), findsOneWidget);
    expect(find.textContaining('Status: Unreachable'), findsOneWidget);
    expect(find.text('Try a protected route'), findsOneWidget);
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
