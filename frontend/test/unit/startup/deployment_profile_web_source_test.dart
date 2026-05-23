import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_web_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sampleProfileJson =
    '{"deployment_mode":"local","supabase_url":"http://127.0.0.1:54321","supabase_anon_key":"test-anon-key"}';

void main() {
  group('resolveDeploymentProfileContents', () {
    test('returns fetched profile and caches it for web startup', () async {
      var cachedPayload = '';
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/deployment-profile.json'));
        return http.Response(_sampleProfileJson, 200);
      });

      final contents = await resolveDeploymentProfileContents(
        client: client,
        baseUri: Uri.parse('http://localhost:8080/'),
        readCachedContents: () async => null,
        writeCachedContents: (value) async {
          cachedPayload = value;
        },
      );

      expect(contents, _sampleProfileJson);
      expect(cachedPayload, _sampleProfileJson);
      expect(DeploymentProfile.fromJsonString(contents!, sourcePath: 'web-test'), isNotNull);
    });

    test('falls back to cached browser storage when origin fetch fails', () async {
      final client = MockClient((request) async => http.Response('Not found', 404));

      final contents = await resolveDeploymentProfileContents(
        client: client,
        baseUri: Uri.parse('http://localhost:8080/'),
        readCachedContents: () async => _sampleProfileJson,
        writeCachedContents: (_) async {},
      );

      expect(contents, _sampleProfileJson);
    });

    test('returns null when neither origin nor cache has a profile', () async {
      final client = MockClient((request) async => http.Response('Not found', 404));

      final contents = await resolveDeploymentProfileContents(
        client: client,
        baseUri: Uri.parse('http://localhost:8080/'),
        readCachedContents: () async => null,
        writeCachedContents: (_) async {},
      );

      expect(contents, isNull);
    });
  });
}
