import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// §13.5 client contract suite — every declared manifest key must resolve.
Future<void> runContextContractSuite({
  required FakeActiveManifestSource manifestSource,
  required ContextResolver resolver,
}) async {
  final body = manifestSource.discoveryBody();
  final manifests = body['manifests']! as List<Object?>;
  for (final manifestValue in manifests) {
    final manifest = manifestValue as Map<String, Object?>;
    final requirements =
        manifest['Context requirements']! as List<Object?>;
    for (final requirementValue in requirements) {
      final requirement = requirementValue as Map<String, Object?>;
      final key = requirement['key']! as String;
      if (!registeredContextKeys.contains(key)) {
        throw ContextContractFailure.unregisteredKey(key);
      }
      final result = await resolver.resolve([key]);
      if (result is! ContextResolveSuccess) {
        throw ContextContractFailure.unresolvableKey(key);
      }
    }
  }
}

class ContextContractFailure implements Exception {
  ContextContractFailure._(this.message);

  factory ContextContractFailure.unregisteredKey(String key) =>
      ContextContractFailure._('Manifest declares unregistered key: $key');

  factory ContextContractFailure.unresolvableKey(String key) =>
      ContextContractFailure._('Resolver could not satisfy key: $key');

  final String message;

  @override
  String toString() => message;
}

void main() {
  group('Context contract suite', () {
    test('contract_every_active_manifest_key_resolvable', () async {
      final manifestSource = FakeActiveManifestSource(
        manifests: [sampleActiveManifest()],
      );
      final resolver = ContextResolver(
        providerPort: FakeContextProviderPort(),
      );

      await expectLater(
        runContextContractSuite(
          manifestSource: manifestSource,
          resolver: resolver,
        ),
        completes,
      );
      resolver.dispose();
    });

    test('contract_manifest_unknown_key_fails_suite', () async {
      final manifestSource = FakeActiveManifestSource(
        manifests: [manifestWithUnknownContextKey()],
      );
      final resolver = ContextResolver(
        providerPort: FakeContextProviderPort(),
      );

      await expectLater(
        runContextContractSuite(
          manifestSource: manifestSource,
          resolver: resolver,
        ),
        throwsA(isA<ContextContractFailure>()),
      );
      resolver.dispose();
    });
  });
}
