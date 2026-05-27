import 'dart:io' show Platform;

/// VM/desktop/mobile: Flutter test runner sets FLUTTER_TEST=true.
bool isFlutterTestRuntimeFromEnvironment() => Platform.environment['FLUTTER_TEST'] == 'true';

/// Live Supabase boundary tests opt in via [AICLINIC_BOUNDARY_INTEGRATION=1].
bool isBoundaryIntegrationFromEnvironment() => Platform.environment['AICLINIC_BOUNDARY_INTEGRATION'] == '1';
