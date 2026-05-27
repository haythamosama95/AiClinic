import 'package:ai_clinic/app/services/startup_health_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('StartupHealthService web-safe probes', () {
    test('marks endpoint reachable when status is below 500', () async {
      final client = MockClient((request) async => http.Response('ok', 200));
      final service = StartupHealthService(client: client, timeout: const Duration(seconds: 1));

      final check = await service.probeEndpointForTest(
        name: 'auth',
        uri: Uri.parse('http://127.0.0.1:54321/auth/v1/health'),
        apiKey: 'anon-key',
      );

      expect(check.reachable, isTrue);
      expect(check.statusCode, 200);
      expect(check.detail, 'HTTP 200');
    });

    test('marks endpoint unreachable when status is 502', () async {
      final client = MockClient((request) async => http.Response('bad gateway', 502));
      final service = StartupHealthService(client: client, timeout: const Duration(seconds: 1));

      final check = await service.probeEndpointForTest(
        name: 'auth',
        uri: Uri.parse('http://127.0.0.1:54321/auth/v1/health'),
        apiKey: 'anon-key',
      );

      expect(check.reachable, isFalse);
      expect(check.statusCode, 502);
    });

    test('uses trailing slash for PostgREST root probes', () async {
      Uri? requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response('ok', 200);
      });
      final service = StartupHealthService(client: client, timeout: const Duration(seconds: 1));

      await service.probeEndpointForTest(
        name: 'api',
        uri: Uri.parse('http://127.0.0.1:54321/rest/v1/'),
        apiKey: 'anon-key',
      );

      expect(requestedUri?.path, '/rest/v1/');
    });

    test('marks endpoint unreachable on client transport failure', () async {
      final client = MockClient((request) async {
        throw http.ClientException('Failed host lookup');
      });
      final service = StartupHealthService(client: client, timeout: const Duration(seconds: 1));

      final check = await service.probeEndpointForTest(
        name: 'api',
        uri: Uri.parse('http://127.0.0.1:54321/rest/v1/'),
        apiKey: 'anon-key',
      );

      expect(check.reachable, isFalse);
      expect(check.detail, contains('Failed host lookup'));
    });
  });
}
