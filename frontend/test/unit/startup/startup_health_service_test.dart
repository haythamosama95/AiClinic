import 'dart:io';

import 'package:ai_clinic/shared/services/startup_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyStartupConnectivity', () {
    test('healthy when auth and api both respond below 500', () {
      final status = classifyStartupConnectivity([
        StartupDependencyCheck(name: 'api', uri: Uri.parse('http://x/rest/v1/'), reachable: true, statusCode: 200),
        StartupDependencyCheck(
          name: 'auth',
          uri: Uri.parse('http://x/auth/v1/health'),
          reachable: true,
          statusCode: 200,
        ),
      ]);

      expect(status, StartupConnectivityStatus.healthy);
    });

    test('unreachable when auth returns 502 even if api is up', () {
      final status = classifyStartupConnectivity([
        StartupDependencyCheck(name: 'api', uri: Uri.parse('http://x/rest/v1/'), reachable: true, statusCode: 200),
        StartupDependencyCheck(
          name: 'auth',
          uri: Uri.parse('http://x/auth/v1/health'),
          reachable: false,
          statusCode: HttpStatus.badGateway,
          detail: 'HTTP 502',
        ),
      ]);

      expect(status, StartupConnectivityStatus.unreachable);
    });

    test('degraded when auth is up but api fails', () {
      final status = classifyStartupConnectivity([
        StartupDependencyCheck(
          name: 'api',
          uri: Uri.parse('http://x/rest/v1/'),
          reachable: false,
          statusCode: HttpStatus.serviceUnavailable,
        ),
        StartupDependencyCheck(
          name: 'auth',
          uri: Uri.parse('http://x/auth/v1/health'),
          reachable: true,
          statusCode: 200,
        ),
      ]);

      expect(status, StartupConnectivityStatus.degraded);
    });

    test('unknown when required probes are missing', () {
      expect(classifyStartupConnectivity([]), StartupConnectivityStatus.unknown);
    });
  });

  group('StartupHealthResult.userMessage', () {
    test('unreachable message mentions supabase restart', () {
      final result = StartupHealthResult(
        status: StartupConnectivityStatus.unreachable,
        checkedAt: DateTime(2026, 5, 21),
        checks: [],
      );

      expect(result.userMessage, contains('supabase stop'));
      expect(result.userMessage, contains('supabase start'));
    });
  });
}
