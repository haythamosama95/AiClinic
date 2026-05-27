import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store.dart';
import 'package:ai_clinic/core/config/deployment_profile_web_source.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Returns the web profile source label shown in startup diagnostics.
String resolveDeploymentProfilePath() => 'web/${DeploymentProfileStore.fileName}';

/// Loads the deployment profile from the web origin or cached browser storage.
Future<DeploymentProfile> loadDeploymentProfile() async {
  const fileName = DeploymentProfileStore.fileName;
  final client = http.Client();

  try {
    final prefs = await SharedPreferences.getInstance();
    final contents = await resolveDeploymentProfileContents(
      client: client,
      baseUri: Uri.base,
      readCachedContents: () async => prefs.getString(deploymentProfileWebCacheKey),
      writeCachedContents: (value) => prefs.setString(deploymentProfileWebCacheKey, value),
    );

    if (contents == null) {
      throw MissingDeploymentProfileException(
        'No deployment profile was found for web startup. Place `$fileName` in the `web/` folder '
        '(served at `/deployment-profile.json`) or configure the profile in browser storage, then retry.',
      );
    }

    return DeploymentProfile.fromJsonString(contents, sourcePath: Uri.base.resolve(fileName).toString());
  } finally {
    client.close();
  }
}
