import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/core/errors/failures.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';

// Sentinel used by copyWith so nullable fields can be preserved intentionally.
const Object _noChange = Object();

/// Tracks whether startup configuration has been resolved successfully yet.
enum StartupConfigurationStatus { unknown, valid, missing, invalid }

/// Drives which safe pre-auth screen the router should expose.
enum StartupCurrentView { startupCheck, unauthenticatedEntry, setupGuidance, protectedRouteBlocked }

@immutable
/// Aggregates the startup state needed by the router and bootstrap UI.
class StartupSessionState {
  const StartupSessionState({
    required this.configurationStatus,
    required this.connectivityStatus,
    required this.currentView,
    required this.themeMode,
    this.blockedReason,
    this.lastHealthCheck,
    this.deploymentProfile,
    this.failure,
    this.healthResult,
  });

  /// Default state shown while bootstrap is still probing local requirements.
  factory StartupSessionState.initial() {
    return const StartupSessionState(
      configurationStatus: StartupConfigurationStatus.unknown,
      connectivityStatus: StartupConnectivityStatus.unknown,
      currentView: StartupCurrentView.startupCheck,
      themeMode: ThemeMode.system,
    );
  }

  final StartupConfigurationStatus configurationStatus;
  final StartupConnectivityStatus connectivityStatus;
  final StartupCurrentView currentView;
  final ThemeMode themeMode;
  final String? blockedReason;
  final DateTime? lastHealthCheck;
  final DeploymentProfile? deploymentProfile;
  final AppFailure? failure;
  final StartupHealthResult? healthResult;

  /// Returns a new state while allowing nullable fields to be cleared explicitly.
  StartupSessionState copyWith({
    StartupConfigurationStatus? configurationStatus,
    StartupConnectivityStatus? connectivityStatus,
    StartupCurrentView? currentView,
    ThemeMode? themeMode,
    Object? blockedReason = _noChange,
    Object? lastHealthCheck = _noChange,
    Object? deploymentProfile = _noChange,
    Object? failure = _noChange,
    Object? healthResult = _noChange,
  }) {
    return StartupSessionState(
      configurationStatus: configurationStatus ?? this.configurationStatus,
      connectivityStatus: connectivityStatus ?? this.connectivityStatus,
      currentView: currentView ?? this.currentView,
      themeMode: themeMode ?? this.themeMode,
      blockedReason: identical(blockedReason, _noChange) ? this.blockedReason : blockedReason as String?,
      lastHealthCheck: identical(lastHealthCheck, _noChange) ? this.lastHealthCheck : lastHealthCheck as DateTime?,
      deploymentProfile: identical(deploymentProfile, _noChange)
          ? this.deploymentProfile
          : deploymentProfile as DeploymentProfile?,
      failure: identical(failure, _noChange) ? this.failure : failure as AppFailure?,
      healthResult: identical(healthResult, _noChange) ? this.healthResult : healthResult as StartupHealthResult?,
    );
  }
}

/// Provides the file-based profile loader used during bootstrap.
final deploymentProfileStoreProvider = Provider<DeploymentProfileStore>((ref) {
  return const DeploymentProfileStore();
});

/// Provides the network probe service used to classify startup connectivity.
final startupHealthServiceProvider = Provider<StartupHealthService>((ref) {
  return const StartupHealthService();
});

/// Owns the startup state machine for bootstrap, retry, theming, and route guards.
final startupSessionProvider = NotifierProvider<StartupSessionNotifier, StartupSessionState>(
  StartupSessionNotifier.new,
);

class StartupSessionNotifier extends Notifier<StartupSessionState> {
  @override
  StartupSessionState build() => StartupSessionState.initial();

  /// Re-runs startup from scratch, loading config first and then probing connectivity.
  Future<void> bootstrap() async {
    final preservedThemeMode = state.themeMode;
    state = StartupSessionState.initial().copyWith(themeMode: preservedThemeMode);

    try {
      final profile = await ref.read(deploymentProfileStoreProvider).load();
      final supabaseConfig = SupabaseConfig.fromDeploymentProfile(profile);
      await SupabaseBootstrap.ensureInitialized(supabaseConfig);
      final healthResult = await ref.read(startupHealthServiceProvider).check(supabaseConfig);

      // A valid profile always advances to the startup dashboard, even if health is degraded.
      state = state.copyWith(
        configurationStatus: StartupConfigurationStatus.valid,
        connectivityStatus: healthResult.status,
        currentView: StartupCurrentView.unauthenticatedEntry,
        blockedReason: healthResult.status == StartupConnectivityStatus.healthy ? null : healthResult.userMessage,
        lastHealthCheck: healthResult.checkedAt,
        deploymentProfile: profile,
        failure: healthResult.status == StartupConnectivityStatus.healthy
            ? null
            : ConnectivityFailure(healthResult.userMessage),
        healthResult: healthResult,
      );
      // Known configuration errors always send the user to setup guidance.
    } on MissingDeploymentProfileException catch (error) {
      _applyConfigurationFailure(status: StartupConfigurationStatus.missing, error: error);
    } on InvalidDeploymentProfileException catch (error) {
      _applyConfigurationFailure(status: StartupConfigurationStatus.invalid, error: error);
    } on DeploymentProfileException catch (error) {
      _applyConfigurationFailure(status: StartupConfigurationStatus.invalid, error: error);
    } catch (error) {
      // Unknown bootstrap failures are treated as unsafe configuration problems.
      state = state.copyWith(
        configurationStatus: StartupConfigurationStatus.invalid,
        connectivityStatus: StartupConnectivityStatus.unknown,
        currentView: StartupCurrentView.setupGuidance,
        blockedReason: 'Startup stopped because configuration could not be resolved safely.',
        lastHealthCheck: null,
        deploymentProfile: null,
        failure: mapExceptionToFailure(error),
        healthResult: null,
      );
    }
  }

  /// Convenience action for re-running the full bootstrap sequence.
  Future<void> retryStartup() => bootstrap();

  /// Updates the pre-auth theme choice without affecting other startup state.
  void setThemeMode(ThemeMode themeMode) {
    state = state.copyWith(themeMode: themeMode);
  }

  /// Records why a protected location was rejected before authentication exists.
  void blockProtectedRoute(String attemptedLocation) {
    state = state.copyWith(
      currentView: StartupCurrentView.protectedRouteBlocked,
      blockedReason: 'Protected route `$attemptedLocation` is unavailable until authenticated workflows exist.',
    );
  }

  /// Returns from the block screen to whichever safe startup view still applies.
  void acknowledgeProtectedRouteBlock() {
    state = state.copyWith(
      currentView: state.configurationStatus == StartupConfigurationStatus.valid
          ? StartupCurrentView.unauthenticatedEntry
          : StartupCurrentView.setupGuidance,
      blockedReason: null,
    );
  }

  /// Applies a consistent setup-guidance state for profile-related failures.
  void _applyConfigurationFailure({
    required StartupConfigurationStatus status,
    required DeploymentProfileException error,
  }) {
    state = state.copyWith(
      configurationStatus: status,
      connectivityStatus: StartupConnectivityStatus.unknown,
      currentView: StartupCurrentView.setupGuidance,
      blockedReason: error.toString(),
      lastHealthCheck: null,
      deploymentProfile: null,
      failure: mapExceptionToFailure(error),
      healthResult: null,
    );
  }
}
