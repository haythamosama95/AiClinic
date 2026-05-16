import 'package:flutter/foundation.dart';

import 'package:ai_clinic/core/errors/exceptions.dart';

@immutable
/// UI-friendly error model that can be rendered without exposing implementation details.
class AppFailure {
  const AppFailure({required this.title, required this.message, this.recoverable = true});

  final String title;
  final String message;
  final bool recoverable;
}

/// Startup failed because local configuration is missing or invalid.
class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure(String message) : super(title: 'Configuration required', message: message);
}

/// Startup reached the local stack but not all services responded cleanly.
class ConnectivityFailure extends AppFailure {
  const ConnectivityFailure(String message) : super(title: 'Connectivity issue', message: message);
}

/// Catch-all failure for unexpected startup problems.
class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(String message)
    : super(title: 'Unexpected startup problem', message: message, recoverable: false);
}

/// Maps low-level exceptions into the smaller set of UI states used by the startup shell.
AppFailure mapExceptionToFailure(Object error) {
  if (error is MissingDeploymentProfileException || error is InvalidDeploymentProfileException) {
    return ConfigurationFailure(error.toString());
  }

  if (error is StartupHealthCheckException) {
    return ConnectivityFailure(error.toString());
  }

  return UnexpectedFailure(error.toString());
}
