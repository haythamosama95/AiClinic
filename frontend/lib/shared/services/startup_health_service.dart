import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/config/supabase_config.dart';

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
    StartupConnectivityStatus.degraded => 'Some clinic-local services are reachable, but startup is degraded.',
    StartupConnectivityStatus.unreachable =>
      'Clinic-local services are currently unreachable. Startup can remain visible, but protected work must stay blocked.',
  };
}

/// Probes the local Supabase gateway endpoints used by the startup shell.
class StartupHealthService {
  const StartupHealthService({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  /// Checks the key gateway, auth, and REST endpoints in parallel.
  Future<StartupHealthResult> check(SupabaseConfig config) async {
    final checks = await Future.wait([
      _probeEndpoint(name: 'gateway', uri: config.gatewayProbeUrl),
      _probeEndpoint(name: 'auth', uri: config.authHealthUrl),
      _probeEndpoint(name: 'rest', uri: config.restProbeUrl),
    ]);

    // The startup UI only needs a simple overall status based on how many probes succeeded.
    final reachableCount = checks.where((check) => check.reachable).length;
    final status = switch (reachableCount) {
      0 => StartupConnectivityStatus.unreachable,
      3 => StartupConnectivityStatus.healthy,
      _ => StartupConnectivityStatus.degraded,
    };

    return StartupHealthResult(status: status, checkedAt: DateTime.now(), checks: checks);
  }

  /// Performs a lightweight GET request and captures the reachability outcome.
  Future<StartupDependencyCheck> _probeEndpoint({required String name, required Uri uri}) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(timeout);
      await response.drain();

      final statusCode = response.statusCode;
      return StartupDependencyCheck(
        name: name,
        uri: uri,
        // Any non-5xx response proves the service is reachable enough for startup diagnostics.
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
