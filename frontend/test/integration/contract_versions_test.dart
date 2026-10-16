import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('E2E-P6.1-07', () {
    test('E2E-P6.1-07 desktop contract constants match package CHANNEL_VERSIONS', () {
      final repoRoot = _repoRoot();
      final packagePath = File('$repoRoot/packages/vendor-contracts/src/version.ts');
      final dartPath = File('$repoRoot/frontend/lib/core/contract_versions.dart');

      expect(
        dartPath.existsSync(),
        isTrue,
        reason: 'missing ${dartPath.path}',
      );

      final packageVersions = _parseChannelVersionsFromTs(packagePath.readAsStringSync());
      final dartVersions = _parseChannelVersionsFromDart(dartPath.readAsStringSync());

      expect(dartVersions.keys.toSet(), packageVersions.keys.toSet());
      for (final key in packageVersions.keys) {
        expect(
          dartVersions[key],
          packageVersions[key],
          reason: 'contract_versions.dart $key must match CHANNEL_VERSIONS.$key',
        );
      }
    });
  });
}

String _repoRoot() {
  final cwd = Directory.current;
  if (File('${cwd.path}/pubspec.yaml').existsSync()) {
    return cwd.parent.path;
  }
  return cwd.path;
}

Map<String, int> _parseChannelVersionsFromTs(String source) {
  final block = RegExp(
    r'CHANNEL_VERSIONS\s*=\s*\{([^}]*)\}',
    multiLine: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: 'CHANNEL_VERSIONS object not found in version.ts');

  final versions = <String, int>{};
  final entryPattern = RegExp(r'(\w+)\s*:\s*(\d+)');
  for (final match in entryPattern.allMatches(block!.group(1)!)) {
    versions[match.group(1)!] = int.parse(match.group(2)!);
  }
  expect(versions, isNotEmpty, reason: 'CHANNEL_VERSIONS parsed empty from version.ts');
  return versions;
}

Map<String, int> _parseChannelVersionsFromDart(String source) {
  final versions = <String, int>{};
  final entryPattern = RegExp(r'(?:static\s+)?const\s+(?:int\s+)?(\w+)\s*=\s*(\d+)');
  for (final match in entryPattern.allMatches(source)) {
    versions[match.group(1)!] = int.parse(match.group(2)!);
  }
  return versions;
}
