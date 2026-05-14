import 'package:flutter/foundation.dart';

import '../errors/exceptions.dart';
import 'deployment_profile.dart';

@immutable
/// Startup-ready connection settings derived from a validated deployment profile.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey, this.aiServiceUrl});

  final Uri url;
  final String anonKey;
  final Uri? aiServiceUrl;

  /// Creates the runtime config only for the currently supported local profile type.
  factory SupabaseConfig.fromDeploymentProfile(DeploymentProfile profile) {
    if (!profile.isLocalOnly) {
      throw const InvalidDeploymentProfileException('Only clinic-local deployment profiles are supported in V1-0.');
    }

    return SupabaseConfig(
      url: profile.supabaseUrl,
      anonKey: profile.supabaseAnonKey,
      aiServiceUrl: profile.aiServiceUrl,
    );
  }

  /// Root gateway URL used as the broadest startup reachability probe.
  Uri get gatewayProbeUrl => url;

  /// Health endpoint used to verify the auth service behind the gateway.
  Uri get authHealthUrl => appendPath('auth/v1/health');

  /// REST endpoint used to verify PostgREST availability.
  Uri get restProbeUrl => appendPath('rest/v1/');

  /// Appends a path segment without losing the base profile URL context.
  Uri appendPath(String path) {
    final combinedSegments = <String>[
      ...url.pathSegments.where((segment) => segment.isNotEmpty),
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ];

    return url.replace(pathSegments: combinedSegments);
  }
}
