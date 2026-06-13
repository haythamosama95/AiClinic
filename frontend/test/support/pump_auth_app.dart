import 'package:ai_clinic/app/app.dart';
import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';
import '../helpers/startup_test_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Boots the full app with startup fakes and extra provider overrides.
Future<void> pumpAuthApp(
  WidgetTester tester, {
  DeploymentProfile? profile,
  DeploymentProfileException? profileError,
  StartupHealthResult? healthResult,
  List extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deploymentProfileStoreProvider.overrideWithValue(
          FakeDeploymentProfileStore(profile: profile, error: profileError),
        ),
        startupHealthServiceProvider.overrideWithValue(FakeStartupHealthService(healthResult ?? sampleHealthResult())),
        ...integrationTestOverrides(),
        ...extraOverrides,
      ],
      child: const AiClinicApp(),
    ),
  );
}
