import 'package:http/http.dart' as http;

/// SharedPreferences key used to cache the last successful web profile payload.
const deploymentProfileWebCacheKey = 'ai_clinic_deployment_profile_json';

/// Resolves deployment profile JSON for web targets.
///
/// Tries the app origin first, then falls back to cached browser storage.
Future<String?> resolveDeploymentProfileContents({
  required http.Client client,
  required Uri baseUri,
  required Future<String?> Function() readCachedContents,
  required Future<void> Function(String contents) writeCachedContents,
  Duration fetchTimeout = const Duration(seconds: 5),
}) async {
  final profileUri = baseUri.resolve('deployment-profile.json');

  try {
    final response = await client.get(profileUri).timeout(fetchTimeout);
    if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
      await writeCachedContents(response.body);
      return response.body;
    }
  } on Exception {
    // Fall back to cached browser storage below.
  }

  final cached = await readCachedContents();
  if (cached != null && cached.trim().isNotEmpty) {
    return cached;
  }

  return null;
}
