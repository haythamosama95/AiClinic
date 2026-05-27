import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store.dart';
import 'package:ai_clinic/core/errors/failures.dart';
import 'package:ai_clinic/app/providers/connectivity_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/services/startup_health_service.dart';

/// Presentation-facing startup state derived from the shared session model.
@immutable
class StartupUiState {
  const StartupUiState({required this.session});

  final StartupSessionState session;

  StartupConfigurationStatus get configurationStatus => session.configurationStatus;

  StartupConnectivityStatus get connectivityStatus => session.connectivityStatus;

  StartupCurrentView get currentView => session.currentView;

  ThemeMode get themeMode => session.themeMode;

  DeploymentProfile? get deploymentProfile => session.deploymentProfile;

  AppFailure? get failure => session.failure;

  StartupHealthResult? get healthResult => session.healthResult;

  String? get blockedReason => session.blockedReason;

  DateTime? get lastHealthCheck => session.lastHealthCheck;

  bool get hasValidConfiguration => configurationStatus == StartupConfigurationStatus.valid;

  bool get showDegradedNotice =>
      hasValidConfiguration &&
      (connectivityStatus == StartupConnectivityStatus.degraded ||
          connectivityStatus == StartupConnectivityStatus.unreachable);

  bool get showConnectivityFailure => failure is ConnectivityFailure;

  List<String> get deploymentProfileLines => [
    'Configuration: ${configurationStatusLabel(configurationStatus)}',
    'Mode: ${deploymentProfile?.deploymentMode.wireValue ?? 'unknown'}',
    'Profile file: ${deploymentProfile?.sourcePath ?? DeploymentProfileStore.localProfilePath}',
    'Supabase URL: ${deploymentProfile?.supabaseUrl ?? 'unavailable'}',
  ];

  List<String> get connectivityLines => [
    'Status: ${connectivityStatusLabel(connectivityStatus)}',
    ?switch (lastHealthCheck) {
      final DateTime checkedAt => 'Last check: ${checkedAt.toLocal()}',
      null => null,
    },
    ?blockedReason,
    ...?healthResult?.checks.map((check) => '${check.name}: ${check.detail ?? 'No detail'} (${check.uri})'),
  ];
}

/// Maps startup session state into UI-ready presentation values and actions.
final startupNotifierProvider = NotifierProvider<StartupNotifier, StartupUiState>(StartupNotifier.new);

class StartupNotifier extends Notifier<StartupUiState> {
  @override
  StartupUiState build() {
    final session = ref.watch(startupSessionProvider);
    return StartupUiState(session: session);
  }

  Future<void> bootstrap() {
    return ref.read(startupSessionProvider.notifier).bootstrap();
  }

  Future<void> retryStartup() => bootstrap();

  void setThemeMode(ThemeMode themeMode) {
    ref.read(startupSessionProvider.notifier).setThemeMode(themeMode);
  }

  void blockProtectedRoute(String attemptedLocation) {
    ref.read(startupSessionProvider.notifier).blockProtectedRoute(attemptedLocation);
  }

  void acknowledgeProtectedRouteBlock() {
    ref.read(startupSessionProvider.notifier).acknowledgeProtectedRouteBlock();
  }
}

/// Converts configuration state into human-readable UI copy.
String configurationStatusLabel(StartupConfigurationStatus status) {
  return switch (status) {
    StartupConfigurationStatus.unknown => 'Unknown',
    StartupConfigurationStatus.valid => 'Valid',
    StartupConfigurationStatus.missing => 'Missing',
    StartupConfigurationStatus.invalid => 'Invalid',
  };
}
