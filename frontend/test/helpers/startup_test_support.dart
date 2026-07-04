// Test-only helpers; not imported by production code.
// ignore_for_file: depend_on_referenced_packages

import 'package:ai_clinic/core/config/deployment_profile.dart';

/// Valid local profile used by startup unit tests.
DeploymentProfile sampleDeploymentProfile({String? sourcePath}) {
  return DeploymentProfile(
    deploymentMode: DeploymentMode.local,
    supabaseUrl: Uri.parse('http://127.0.0.1:54321'),
    supabaseAnonKey: 'test-anon-key',
    sourcePath: sourcePath ?? 'test/deployment-profile.json',
  );
}
