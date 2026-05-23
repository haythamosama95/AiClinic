import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_web_source.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_clinic/testing/startup_test_support.dart';

const _webProfileJson =
    '{"deployment_mode":"local","supabase_url":"http://127.0.0.1:54321","supabase_anon_key":"test-anon-key"}';

void main() {
  group('web startup bootstrap', () {
    test('parses a web-served deployment profile payload', () {
      final profile = DeploymentProfile.fromJsonString(_webProfileJson, sourcePath: 'web/deployment-profile.json');

      expect(profile.supabaseUrl, Uri.parse('http://127.0.0.1:54321'));
      expect(profile.supabaseAnonKey, 'test-anon-key');
      expect(profile.isLocalOnly, isTrue);
    });

    test('resolves profile from web origin before bootstrap UI renders', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/deployment-profile.json'));
        return http.Response(_webProfileJson, 200);
      });

      final contents = await resolveDeploymentProfileContents(
        client: client,
        baseUri: Uri.parse('http://localhost:8080/'),
        readCachedContents: () async => null,
        writeCachedContents: (_) async {},
      );

      expect(contents, _webProfileJson);
    });

    testWidgets('shows startup entry after web-safe bootstrap overrides', (tester) async {
      await pumpStartupApp(
        tester,
        profile: sampleDeploymentProfile(sourcePath: 'web/deployment-profile.json'),
        healthResult: sampleHealthResult(),
      );
      await completeStartupBootstrap(tester);

      expect(find.text('AiClinic clinic-local startup'), findsOneWidget);
      expect(find.text('Setup guidance required'), findsNothing);
      expect(find.textContaining('web/deployment-profile.json'), findsOneWidget);
      expect(find.textContaining('Status: Healthy'), findsOneWidget);
    });

    testWidgets('shows web setup guidance when profile is missing', (tester) async {
      await pumpStartupApp(
        tester,
        profileError: const MissingDeploymentProfileException(
          'No deployment profile was found for web startup. Place `deployment-profile.json` in the `web/` folder.',
        ),
      );
      await completeStartupBootstrap(tester);

      expect(find.text('Setup guidance required'), findsOneWidget);
      expect(find.text('Retry bootstrap'), findsOneWidget);
      expect(find.textContaining('deployment-profile.json'), findsWidgets);
    });
  });
}
