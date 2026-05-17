import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';

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

/// Initializes Supabase without restoring sessions from platform storage.
class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static bool _initialized = false;

  static Future<void> ensureInitialized(SupabaseConfig config) async {
    if (_initialized && Supabase.instance.isInitialized) {
      return;
    }

    await Supabase.initialize(
      url: config.url.toString(),
      anonKey: config.anonKey,
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );

    // Cold start must not keep a prior workstation session in memory.
    await Supabase.instance.client.auth.signOut();
    _initialized = true;
  }
}

/// Riverpod access to the initialized Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!Supabase.instance.isInitialized) {
    throw StateError('Supabase has not been initialized. Complete startup bootstrap first.');
  }
  return Supabase.instance.client;
});

/// Decodes JWT custom claims issued by `get_custom_claims`.
Map<String, dynamic> decodeAccessTokenClaims(String accessToken) {
  final parts = accessToken.split('.');
  if (parts.length < 2) {
    return const {};
  }

  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = utf8.decode(base64Url.decode(normalized));
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      return const {};
    }
    return decoded;
  } on FormatException {
    return const {};
  } on Exception {
    return const {};
  }
}
