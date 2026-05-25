/// Web and other non-IO targets: no access to [dart:io] environment variables.
bool isFlutterTestRuntimeFromEnvironment() => false;

/// Boundary integration runs on VM/desktop tests only.
bool isBoundaryIntegrationFromEnvironment() => false;
