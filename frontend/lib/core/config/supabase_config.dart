import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ai_clinic/core/config/supabase_config_env_stub.dart'
    if (dart.library.io) 'package:ai_clinic/core/config/supabase_config_env_io.dart'
    as supabase_config_env;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/in_memory_gotrue_async_storage.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:ai_clinic/core/logging/app_log.dart';

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

  /// GoTrue health endpoint (required for staff sign-in).
  Uri get authHealthUrl => appendPath('auth/v1/health');

  /// PostgREST OpenAPI root used as the API availability probe (Kong root often returns 404).
  ///
  /// The trailing slash is required: `/rest/v1` is a Kong 404 without CORS headers, which
  /// browsers report as "Failed to fetch" during web startup probes.
  Uri get restProbeUrl {
    final base = appendPath('rest/v1');
    return base.replace(path: '${base.path}/');
  }

  /// Appends a path segment without losing the base profile URL context.
  Uri appendPath(String path) {
    final combinedSegments = <String>[
      ...url.pathSegments.where((segment) => segment.isNotEmpty),
      ...path.split('/').where((segment) => segment.isNotEmpty),
    ];

    return url.replace(pathSegments: combinedSegments);
  }
}

bool _isFlutterTestRuntime() => supabase_config_env.isFlutterTestRuntimeFromEnvironment();

bool _isBoundaryIntegration() => supabase_config_env.isBoundaryIntegrationFromEnvironment();

bool _useTestStub() => _isFlutterTestRuntime() && !_isBoundaryIntegration();

/// Initializes Supabase without restoring sessions from platform storage.
class SupabaseBootstrap {
  const SupabaseBootstrap._();

  static bool _initialized = false;
  static Future<void>? _pendingInitialization;

  /// Whether [ensureInitialized] completed successfully for this process.
  ///
  /// Do not use [Supabase.instance] to check readiness — the SDK throws before init.
  static bool get isReady {
    if (_useTestStub() && _testReady) {
      return true;
    }

    return _initialized;
  }

  static bool _testReady = false;

  /// Marks bootstrap complete for widget tests without calling the real Supabase SDK.
  @visibleForTesting
  static void debugMarkReadyForTests() {
    _testReady = true;
    _initialized = true;
  }

  @visibleForTesting
  static void debugResetForTests() {
    _testReady = false;
    _initialized = false;
    _pendingInitialization = null;
  }

  /// Ensures a single in-flight initialization; clears the pending future on failure so callers can retry.
  static Future<void> ensureInitialized(SupabaseConfig config) {
    if (isReady) {
      return Future<void>.value();
    }

    if (_useTestStub()) {
      debugMarkReadyForTests();
      return Future<void>.value();
    }

    return _pendingInitialization ??= _initialize(config);
  }

  /// Initializes the real Supabase SDK for live integration/boundary harnesses.
  ///
  /// Unlike [ensureInitialized], this never uses the unit-test stub because harness
  /// code must call [Supabase.instance] after sign-in probes.
  static Future<void> ensureLiveInitialized(SupabaseConfig config) {
    if (_initialized && !_testReady) {
      return Future<void>.value();
    }

    debugResetForTests();
    return _pendingInitialization ??= _initialize(config);
  }

  static Future<void> _initialize(SupabaseConfig config) async {
    try {
      await Supabase.initialize(
        url: config.url.toString(),
        publishableKey: config.anonKey,
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          // Avoid SharedPreferences in headless `flutter test` (boundary suite).
          pkceAsyncStorage: InMemoryGotrueAsyncStorage(),
        ),
      );
      _initialized = true;
      AppLog.info('supabase.bootstrap.ready');
    } catch (error) {
      _initialized = false;
      _pendingInitialization = null;
      AppLog.warning('supabase.bootstrap.failed reason=${error.runtimeType}');
      rethrow;
    }
  }
}

/// Riverpod access to the initialized Supabase client.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!SupabaseBootstrap.isReady) {
    throw StateError('Supabase has not been initialized. Complete startup bootstrap first.');
  }
  return Supabase.instance.client;
});

/// Outcome of decoding a Supabase access-token JWT payload.
sealed class AccessTokenClaimsDecodeResult {
  const AccessTokenClaimsDecodeResult();

  /// Claim map when decoding succeeded; empty for [AccessTokenClaimsExpired] and
  /// [AccessTokenClaimsInvalid].
  Map<String, dynamic> get claims => switch (this) {
    AccessTokenClaimsSuccess(:final claims) => claims,
    AccessTokenClaimsExpired() || AccessTokenClaimsInvalid() => const {},
  };

  bool get isSuccess => this is AccessTokenClaimsSuccess;
}

/// Valid, non-expired JWT with custom claims from `get_custom_claims`.
final class AccessTokenClaimsSuccess extends AccessTokenClaimsDecodeResult {
  const AccessTokenClaimsSuccess(this.claims);

  @override
  final Map<String, dynamic> claims;
}

/// JWT `exp` is in the past (clock skew, paused app, stale persisted session).
final class AccessTokenClaimsExpired extends AccessTokenClaimsDecodeResult {
  const AccessTokenClaimsExpired();
}

/// Malformed token, non-object payload, or other decode failure.
final class AccessTokenClaimsInvalid extends AccessTokenClaimsDecodeResult {
  const AccessTokenClaimsInvalid();
}

/// Decodes JWT custom claims issued by `get_custom_claims`.
///
/// Distinguishes expiry from missing/invalid payloads so callers can sign out
/// with an accurate failure category instead of treating expiry as missing claims.
AccessTokenClaimsDecodeResult decodeAccessTokenClaims(String accessToken) {
  final parts = accessToken.split('.');
  if (parts.length < 2) {
    return const AccessTokenClaimsInvalid();
  }

  try {
    final normalized = base64Url.normalize(parts[1]);
    final payload = utf8.decode(base64Url.decode(normalized));
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      return const AccessTokenClaimsInvalid();
    }

    final exp = decoded['exp'];
    if (exp is int) {
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      if (expiryDate.isBefore(DateTime.now().toUtc())) {
        AppLog.warning('supabase.jwt.expired exp=$expiryDate');
        return const AccessTokenClaimsExpired();
      }
    }

    return AccessTokenClaimsSuccess(decoded);
  } on FormatException {
    return const AccessTokenClaimsInvalid();
  } on Exception {
    return const AccessTokenClaimsInvalid();
  }
}
