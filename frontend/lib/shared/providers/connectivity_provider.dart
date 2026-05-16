import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';

/// Exposes clinic-local connectivity classification from the latest startup probe.
final connectivityStatusProvider = Provider<StartupConnectivityStatus>((ref) {
  return ref.watch(startupSessionProvider).connectivityStatus;
});

/// Last structured health result, when bootstrap completed with a valid profile.
final connectivityHealthResultProvider = Provider<StartupHealthResult?>((ref) {
  return ref.watch(startupSessionProvider).healthResult;
});

/// User-facing connectivity label for status surfaces.
String connectivityStatusLabel(StartupConnectivityStatus status) => switch (status) {
  StartupConnectivityStatus.unknown => 'Unknown',
  StartupConnectivityStatus.healthy => 'Healthy',
  StartupConnectivityStatus.degraded => 'Degraded',
  StartupConnectivityStatus.unreachable => 'Unreachable',
};
