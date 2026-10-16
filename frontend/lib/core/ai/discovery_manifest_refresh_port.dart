import 'context_required_self_heal.dart';
import 'discovery_client.dart';
import 'ports.dart';

/// Production [ManifestRefreshPort] backed by I3 [DiscoveryClient] (I4).
class DiscoveryManifestRefreshPort implements ManifestRefreshPort {
  DiscoveryManifestRefreshPort({
    required DiscoveryClient discoveryClient,
    required AatMintPort mintPort,
    required String platformBaseUrl,
    List<Map<String, Object?>> initialManifests = const [],
  })  : _discoveryClient = discoveryClient,
        _mintPort = mintPort,
        _platformBaseUrl = platformBaseUrl,
        _manifests = List<Map<String, Object?>>.from(initialManifests);

  final DiscoveryClient _discoveryClient;
  final AatMintPort _mintPort;
  final String _platformBaseUrl;
  List<Map<String, Object?>> _manifests;

  @override
  Future<void> refresh() async {
    final aat = await _mintPort.mint();
    final result = await _discoveryClient.fetchCapabilities(
      platformBaseUrl: _platformBaseUrl,
      aat: aat,
    );
    if (!result.notModified && result.manifests.isNotEmpty) {
      _manifests = List<Map<String, Object?>>.from(result.manifests);
    }
  }

  @override
  InteractionMode interactionModeFor(String capabilityId) {
    for (final manifest in _manifests) {
      final identity = manifest['Identity'];
      if (identity is Map) {
        final id = identity['capabilityId'] ?? identity['capability_id'];
        if (id == capabilityId) {
          final interaction = manifest['Interaction'];
          if (interaction is Map) {
            final mode = interaction['interactionMode'] ?? interaction['interaction_mode'];
            if (mode == 'conversational') {
              return InteractionMode.conversational;
            }
          }
          return InteractionMode.singleShot;
        }
      }
    }
    return InteractionMode.singleShot;
  }
}
