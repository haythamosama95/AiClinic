import 'package:flutter/foundation.dart';

@immutable
/// Base exception type for startup and configuration failures surfaced by the app.
class AppException implements Exception {
  const AppException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() {
    if (details == null || details!.isEmpty) {
      return message;
    }

    return '$message ($details)';
  }
}

/// Shared parent type for profile loading and validation errors.
class DeploymentProfileException extends AppException {
  const DeploymentProfileException(super.message, {super.details});
}

/// Thrown when no deployment profile file can be found in any expected location.
class MissingDeploymentProfileException extends DeploymentProfileException {
  const MissingDeploymentProfileException(super.message, {super.details});
}

/// Thrown when a deployment profile exists but fails validation.
class InvalidDeploymentProfileException extends DeploymentProfileException {
  const InvalidDeploymentProfileException(super.message, {super.details});
}

/// Thrown when startup dependency checks cannot complete as expected.
class StartupHealthCheckException extends AppException {
  const StartupHealthCheckException(super.message, {super.details});
}
