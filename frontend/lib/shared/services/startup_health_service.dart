import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:ai_clinic/core/config/supabase_config.dart';

/// High-level connectivity classification for the clinic-local startup probes.
enum StartupConnectivityStatus { unknown, healthy, degraded, unreachable }

@immutable
/// Result of probing a single dependency endpoint during startup.
class StartupDependencyCheck {
  const StartupDependencyCheck({
    required this.name,
    required this.uri,
    required this.reachable,
    this.statusCode,
    this.detail,
  });

  final String name;
  final Uri uri;
  final bool reachable;
  final int? statusCode;
  final String? detail;
}

@immutable
/// Aggregate health snapshot returned after startup probes complete.
class StartupHealthResult {
  const StartupHealthResult({required this.status, required this.checkedAt, required this.checks});

  final StartupConnectivityStatus status;
  final DateTime checkedAt;
  final List<StartupDependencyCheck> checks;

  /// User-facing summary derived from the aggregate connectivity status.
  String get userMessage => switch (status) {
    StartupConnectivityStatus.unknown => 'Startup health has not been checked yet.',
    StartupConnectivityStatus.healthy => 'Clinic-local services are reachable.',
    StartupConnectivityStatus.degraded =>
      'Some clinic-local services responded, but sign-in may not work until all probes succeed.',
    StartupConnectivityStatus.unreachable => _unreachableMessage(),
  };

  static String _unreachableMessage() {
    return 'Clinic-local services are unreachable. If using Supabase CLI, run '
        '`supabase stop` then `supabase start` in the backend folder, then tap Refresh startup checks.';
  }
}

/// Classifies startup probe results: auth and REST must both respond for a healthy clinic-local stack.
StartupConnectivityStatus classifyStartupConnectivity(List<StartupDependencyCheck> checks) {
  final byName = {for (final check in checks) check.name: check};
  final auth = byName['auth'];
  final api = byName['api'];

  if (auth == null || api == null) {
    return StartupConnectivityStatus.unknown;
  }

  if (!auth.reachable) {
    return StartupConnectivityStatus.unreachable;
  }

  if (!api.reachable) {
    return StartupConnectivityStatus.degraded;
  }

  return StartupConnectivityStatus.healthy;
}

/// Probes the local Supabase API and Auth endpoints used by the startup shell.
class StartupHealthService {
  const StartupHealthService({
    this.timeout = const Duration(seconds: 3),
    this.authRetryDelay = const Duration(seconds: 2),
  });

  final Duration timeout;
  final Duration authRetryDelay;

  /// Checks REST and Auth health endpoints (auth is required for sign-in).
  Future<StartupHealthResult> check(SupabaseConfig config) async {
    var authCheck = await _probeEndpoint(name: 'auth', uri: config.authHealthUrl, apiKey: config.anonKey);

    if (!authCheck.reachable && authCheck.statusCode == HttpStatus.badGateway) {
      await Future<void>.delayed(authRetryDelay);
      authCheck = await _probeEndpoint(name: 'auth', uri: config.authHealthUrl, apiKey: config.anonKey);
    }

    final apiCheck = await _probeEndpoint(name: 'api', uri: config.restProbeUrl, apiKey: config.anonKey);

    final checks = [apiCheck, authCheck];
    return StartupHealthResult(status: classifyStartupConnectivity(checks), checkedAt: DateTime.now(), checks: checks);
  }

  /// Performs a lightweight GET request and captures the reachability outcome.
  @visibleForTesting
  Future<StartupDependencyCheck> probeEndpointForTest({
    required String name,
    required Uri uri,
    required String apiKey,
  }) {
    return _probeEndpoint(name: name, uri: uri, apiKey: apiKey);
  }

  Future<StartupDependencyCheck> _probeEndpoint({
    required String name,
    required Uri uri,
    required String apiKey,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('apikey', apiKey);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');

      final response = await request.close().timeout(timeout);
      await response.drain();

      final statusCode = response.statusCode;
      return StartupDependencyCheck(
        name: name,
        uri: uri,
        reachable: statusCode < HttpStatus.internalServerError,
        statusCode: statusCode,
        detail: 'HTTP $statusCode',
      );
    } on TimeoutException {
      return StartupDependencyCheck(
        name: name,
        uri: uri,
        reachable: false,
        detail: 'Timed out after ${timeout.inSeconds}s',
      );
    } on SocketException catch (error) {
      return StartupDependencyCheck(name: name, uri: uri, reachable: false, detail: error.message);
    } on HttpException catch (error) {
      return StartupDependencyCheck(name: name, uri: uri, reachable: false, detail: error.message);
    } finally {
      client.close(force: true);
    }
  }
}
