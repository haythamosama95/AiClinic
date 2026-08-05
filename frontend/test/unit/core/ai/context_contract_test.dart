import 'package:ai_clinic/core/ai/context_registration.dart';
import 'package:ai_clinic/core/ai/context_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'published_manifests.dart';

const _chiefComplaintDeclaredKeys = {
  'visit_id',
  'complaint',
  'recorded_at',
};

/// §13.5 client contract suite — every declared manifest key must resolve,
/// and each resolved payload must be a Map whose known-key shapes hold.
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
      _assertResolvedPayloadShape(key, result.payload);
    }
  }
}

void _assertResolvedPayloadShape(
  String key,
  Map<String, Object?> assembled,
) {
  final value = assembled[key];
  if (value is! Map) {
    throw ContextContractFailure.shapeViolation(
      key,
      'resolved value must be a Map',
    );
  }
  final payload = Map<String, Object?>.from(value);

  if (key == visitChiefComplaintV1Key) {
    _assertVisitChiefComplaintV1Shape(key, payload);
  }
}

void _assertVisitChiefComplaintV1Shape(
  String key,
  Map<String, Object?> payload,
) {
  final undeclared = payload.keys
      .where((k) => !_chiefComplaintDeclaredKeys.contains(k))
      .toList(growable: false);
  if (undeclared.isNotEmpty) {
    throw ContextContractFailure.shapeViolation(
      key,
      'undeclared keys: ${undeclared.join(', ')}',
    );
  }

  final visitId = payload['visit_id'];
  if (visitId is! String) {
    throw ContextContractFailure.shapeViolation(
      key,
      'visit_id must be a required String',
    );
  }

  if (payload.containsKey('complaint')) {
    final complaint = payload['complaint'];
    if (complaint is! String) {
      throw ContextContractFailure.shapeViolation(
        key,
        'complaint must be a String when present',
      );
    }
    if (complaint.length > 10000) {
      throw ContextContractFailure.shapeViolation(
        key,
        'complaint length must be ≤ 10000',
      );
    }
  }

  if (payload.containsKey('recorded_at')) {
    final recordedAt = payload['recorded_at'];
    if (recordedAt is! String) {
      throw ContextContractFailure.shapeViolation(
        key,
        'recorded_at must be a String when present',
      );
    }
  }
}

class ContextContractFailure implements Exception {
  ContextContractFailure._(this.message);

  factory ContextContractFailure.unregisteredKey(String key) =>
      ContextContractFailure._('Manifest declares unregistered key: $key');

  factory ContextContractFailure.unresolvableKey(String key) =>
      ContextContractFailure._('Resolver could not satisfy key: $key');

  factory ContextContractFailure.shapeViolation(String key, String detail) =>
      ContextContractFailure._('Shape violation for $key: $detail');

  final String message;

  @override
  String toString() => message;
}

void main() {
  group('Context contract suite', () {
    test('contract_published_manifests_fixture_agrees_with_platform', () {
      assertPublishedManifestsFixtureAgreesWithPlatform();
    });

    test('contract_every_active_manifest_key_resolvable', () async {
      final discovery = loadPublishedManifestsFixture();
      final manifestSource = FakeActiveManifestSource(
        manifests: manifestsFromDiscovery(discovery),
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
