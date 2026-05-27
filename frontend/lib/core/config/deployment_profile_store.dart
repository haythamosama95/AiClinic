import 'package:ai_clinic/core/config/deployment_profile.dart';
import 'package:ai_clinic/core/config/deployment_profile_store_io.dart'
    if (dart.library.html) 'package:ai_clinic/core/config/deployment_profile_store_web.dart'
    as platform;

/// Loads the clinic deployment profile using the platform-specific store backend.
class DeploymentProfileStore {
  const DeploymentProfileStore();

  /// Web bundle filename (served from `web/`).
  static const fileName = 'deployment-profile.json';

  /// Desktop IO profile path when [AICLINIC_DEPLOYMENT_PROFILE_PATH] is unset.
  static const localProfilePath = 'config/local/deployment-profile.json';

  /// Returns a human-readable profile location label for the current platform.
  String resolvePath() => platform.resolveDeploymentProfilePath();

  /// Loads and validates the deployment profile for the current platform.
  Future<DeploymentProfile> load() => platform.loadDeploymentProfile();
}
