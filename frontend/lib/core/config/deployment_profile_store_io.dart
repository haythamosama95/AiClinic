import 'dart:io';

import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store.dart';
import 'package:ai_clinic/core/errors/exceptions.dart';

/// Returns the profile file name used on IO platforms.
String resolveDeploymentProfilePath() => DeploymentProfileStore.fileName;

/// Loads [DeploymentProfileStore.fileName] from the process working directory.
Future<DeploymentProfile> loadDeploymentProfile() async {
  const fileName = DeploymentProfileStore.fileName;
  final file = File(fileName);
  if (!await file.exists()) {
    throw MissingDeploymentProfileException(
      'No deployment profile was found. Expected `$fileName` in the process working directory. '
      'Create a local profile before startup can continue.',
    );
  }

  final contents = await file.readAsString();
  return DeploymentProfile.fromJsonString(contents, sourcePath: file.path);
}
