import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'import_boundaries_allowlist.dart';

void main() {
  final libDir = Directory('lib');
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final importPattern = RegExp(r"^import\s+'(package:[^']+|dart:[^']+)'");

  const forbiddenDomainImports = <String>{
    'package:flutter/material.dart',
    'package:flutter/widgets.dart',
    'dart:ui',
    'package:supabase_flutter/supabase_flutter.dart',
    'package:syncfusion_flutter_calendar/calendar.dart',
  };

  const forbiddenDomainPrefixes = <String>[
    'package:flutter_riverpod/',
    'package:supabase_flutter/',
    'package:syncfusion_flutter_calendar/',
    'package:ai_clinic/core/ui/',
  ];

  test('core must not import features', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      if (!relativePath.startsWith('lib/core/')) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        if (!importUri.startsWith('package:ai_clinic/features/')) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('domain must not import other features', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      final owningFeature = featureNameForPath(relativePath);
      if (owningFeature == null || !isUnderDomain(relativePath)) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        final importedFeature = featureNameForImport(importUri);
        if (importedFeature == null || importedFeature == owningFeature) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('domain must not import UI, framework, or infrastructure', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      if (featureNameForPath(relativePath) == null || !isUnderDomain(relativePath)) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        if (importUri == 'package:flutter/foundation.dart') {
          continue;
        }
        final forbidden = forbiddenDomainImports.contains(importUri) ||
            forbiddenDomainPrefixes.any(importUri.startsWith);
        if (!forbidden) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('features must not import other features data layer', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      final owningFeature = featureNameForPath(relativePath);
      if (owningFeature == null) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        final importedFeature = featureNameForImport(importUri);
        final importedLayer = featureLayerForImport(importUri);
        if (importedFeature == null ||
            importedLayer != 'data' ||
            importedFeature == owningFeature) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('features must not import other features presentation providers', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      final owningFeature = featureNameForPath(relativePath);
      if (owningFeature == null) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        final importedFeature = featureNameForImport(importUri);
        if (importedFeature == null || importedFeature == owningFeature) {
          continue;
        }
        if (!importUri.startsWith(
          'package:ai_clinic/features/$importedFeature/presentation/providers/',
        )) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('data must not import presentation in the same feature', () {
    final violations = <String>[];

    for (final file in dartFiles) {
      final relativePath = toLibRelativePath(file.path);
      final owningFeature = featureNameForPath(relativePath);
      if (owningFeature == null || !isUnderData(relativePath)) {
        continue;
      }

      for (final importUri in readImportUris(file, importPattern)) {
        if (!importUri.startsWith(
          'package:ai_clinic/features/$owningFeature/presentation/',
        )) {
          continue;
        }
        recordViolation(
          violations,
          relativePath: relativePath,
          importUri: importUri,
        );
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}

String toLibRelativePath(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final libIndex = normalized.indexOf('/lib/');
  if (libIndex == -1) {
    return normalized.startsWith('lib/') ? normalized : 'lib/$normalized';
  }
  return normalized.substring(libIndex + 1);
}

bool isUnderDomain(String relativePath) {
  return RegExp(r'^lib/features/[^/]+/domain/').hasMatch(relativePath);
}

bool isUnderData(String relativePath) {
  return RegExp(r'^lib/features/[^/]+/data/').hasMatch(relativePath);
}

String? featureNameForPath(String relativePath) {
  final match = RegExp(r'^lib/features/([^/]+)/').firstMatch(relativePath);
  return match?.group(1);
}

String? featureNameForImport(String importUri) {
  final match =
      RegExp(r'^package:ai_clinic/features/([^/]+)/').firstMatch(importUri);
  return match?.group(1);
}

String? featureLayerForImport(String importUri) {
  final match = RegExp(
    r'^package:ai_clinic/features/[^/]+/([^/]+)/',
  ).firstMatch(importUri);
  return match?.group(1);
}

List<String> readImportUris(File file, RegExp importPattern) {
  return file
      .readAsLinesSync()
      .map((line) => importPattern.firstMatch(line)?.group(1))
      .whereType<String>()
      .toList();
}

void recordViolation(
  List<String> violations, {
  required String relativePath,
  required String importUri,
}) {
  final key = '$relativePath|$importUri';
  if (importBoundaryAllowlist.containsKey(key)) {
    return;
  }
  violations.add('$relativePath imports $importUri');
}
