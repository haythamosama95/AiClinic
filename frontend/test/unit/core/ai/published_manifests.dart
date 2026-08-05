import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hermetic C1-shaped discovery body derived from
/// `ai-platform/manifests/published/*.json`.
const publishedManifestsFixtureRelativePath =
    'test/fixtures/ai/published_manifests_discovery.json';

/// Resolves the Flutter package root (`frontend/`) from [Directory.current].
String frontendPackageRoot() {
  final dir = Directory.current;
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    return dir.path;
  }
  final nested = Directory('${dir.path}/frontend');
  if (File('${nested.path}/pubspec.yaml').existsSync()) {
    return nested.path;
  }
  throw StateError(
    'Cannot locate frontend package root from ${dir.path}',
  );
}

/// Walks up from the frontend package root to the monorepo root.
String repoRootFromFrontend(String frontendRoot) {
  final parent = Directory(frontendRoot).parent;
  final publishedDir =
      Directory('${parent.path}/ai-platform/manifests/published');
  if (publishedDir.existsSync()) {
    return parent.path;
  }
  throw StateError(
    'Cannot locate repo root (ai-platform/manifests/published) above $frontendRoot',
  );
}

Object? _deepJsonObject(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepJsonObject(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepJsonObject).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _asDiscoveryBody(Object? decoded) {
  final converted = _deepJsonObject(decoded);
  expect(converted, isA<Map<String, Object?>>());
  final body = converted! as Map<String, Object?>;
  expect(body.containsKey('manifests'), isTrue);
  expect(body['manifests'], isA<List<Object?>>());
  return body;
}

Map<String, Object?> loadPublishedManifestsFixture() {
  final path =
      '${frontendPackageRoot()}/$publishedManifestsFixtureRelativePath';
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Missing fixture at $path');
  return _asDiscoveryBody(jsonDecode(file.readAsStringSync()));
}

/// Loads every `*.json` under `ai-platform/manifests/published/` into a
/// C1-shaped `{ "manifests": [...] }` body (sorted by filename for stability).
Map<String, Object?> loadPlatformPublishedManifestsDiscovery() {
  final repoRoot = repoRootFromFrontend(frontendPackageRoot());
  final dir = Directory('$repoRoot/ai-platform/manifests/published');
  expect(dir.existsSync(), isTrue, reason: 'Missing published dir ${dir.path}');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  expect(files, isNotEmpty, reason: 'No published manifests under ${dir.path}');
  final manifests = <Object?>[];
  for (final file in files) {
    manifests.add(_deepJsonObject(jsonDecode(file.readAsStringSync())));
  }
  return {'manifests': manifests};
}

/// Context-requirement keys declared by a C1-shaped discovery body.
List<String> contextRequirementKeys(Map<String, Object?> discoveryBody) {
  final manifests = discoveryBody['manifests']! as List<Object?>;
  final keys = <String>[];
  for (final manifestValue in manifests) {
    final manifest = manifestValue! as Map<String, Object?>;
    final requirements = manifest['Context requirements']! as List<Object?>;
    for (final requirementValue in requirements) {
      final requirement = requirementValue! as Map<String, Object?>;
      keys.add(requirement['key']! as String);
    }
  }
  return keys;
}

List<Map<String, Object?>> manifestsFromDiscovery(
  Map<String, Object?> discoveryBody,
) {
  final manifests = discoveryBody['manifests']! as List<Object?>;
  return [
    for (final m in manifests) Map<String, Object?>.from(m! as Map),
  ];
}

/// Asserts the hermetic fixture agrees with platform published manifests.
void assertPublishedManifestsFixtureAgreesWithPlatform() {
  final fixture = loadPublishedManifestsFixture();
  final published = loadPlatformPublishedManifestsDiscovery();
  expect(
    contextRequirementKeys(fixture),
    orderedEquals(contextRequirementKeys(published)),
    reason:
        'Fixture Context requirements keys drifted from '
        'ai-platform/manifests/published/',
  );
  expect(
    jsonEncode(fixture),
    jsonEncode(published),
    reason:
        'Fixture body drifted from ai-platform/manifests/published/ — regenerate '
        'frontend/test/fixtures/ai/published_manifests_discovery.json',
  );
}
