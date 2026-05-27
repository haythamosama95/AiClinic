import 'dart:io';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';

/// Returns the resolved deployment profile path label for the current platform.
String resolveDeploymentProfilePath() {
  final override = Platform.environment['AICLINIC_DEPLOYMENT_PROFILE_PATH'];
  if (override != null && override.isNotEmpty) {
    return override;
  }
  return DeploymentProfileStore.localProfilePath;
}

Future<File?> _resolveProfileFile() async {
  final override = Platform.environment['AICLINIC_DEPLOYMENT_PROFILE_PATH'];
  if (override != null && override.isNotEmpty) {
    final file = File(override);
    return await file.exists() ? file : null;
  }

  final file = File(DeploymentProfileStore.localProfilePath);
  return await file.exists() ? file : null;
}

/// Loads the deployment profile for IO platforms.
Future<DeploymentProfile> loadDeploymentProfile() async {
  final file = await _resolveProfileFile();
  if (file == null) {
    throw MissingDeploymentProfileException(
      'No deployment profile was found. Set `AICLINIC_DEPLOYMENT_PROFILE_PATH`, '
      'or create `${DeploymentProfileStore.localProfilePath}` '
      '(copy from `config/examples/deployment-profile.example.json`).',
    );
  }

  final contents = await file.readAsString();
  return DeploymentProfile.fromJsonString(contents, sourcePath: file.path);
}
